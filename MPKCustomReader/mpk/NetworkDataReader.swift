import Foundation
import AgoraRtcKit

let key = "keykeykeyaaaasdgt"

class NetworkDataReader: NSObject, URLSessionDataDelegate {
    // MARK: - Properties
    private var downloadedBuffer = Data()         // 存储下载的数据
    private var _currentPosition: Int = 0         // 当前读取位置
    private var _totalBytesReceived: Int = 0      // 总接收字节数
    private var isDownloading = false            // 下载状态标志
    private var isMpkStopped = false            // MPK 停止状态标志
    private var fileSize: Int64 = -1
    private var cacheFilePath: String?           // 缓存文件路径
    private var tempCacheFilePath: String?       // 临时缓存文件路径
    private let readCondition = NSCondition()    // 用于同步读取操作的条件锁
    
    private let isEncrypted: Bool
    private var crypto: XORCrypto!
    private let cacheManager = CacheManager.shared
    
    // 线程安全相关
    private let downloadQueue = DispatchQueue(label: "com.agora.networkdatareader.download", qos: .userInitiated)
    private let readQueue = DispatchQueue(label: "com.agora.networkdatareader.read", qos: .userInitiated)
    private let operationQueue = OperationQueue()
    private var session: URLSession?
    private var downloadTask: URLSessionDataTask?
    private var retryCount = 0
    private let maxRetries = 3
    
    // 回调
    var onProgressUpdate: ((Float) -> Void)?
    
    private var availableBytes: Int {
        readQueue.sync {
            downloadedBuffer.count - _currentPosition
        }
    }
    
    // MARK: - Initialization
    init(isEncrypted: Bool = true) {
        self.isEncrypted = isEncrypted
        super.init()
        
        let keyBytes = key.utf8.map { UInt8($0) }
        self.crypto = XORCrypto(key: keyBytes)
        
        // 配置 OperationQueue
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.qualityOfService = .userInitiated
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: operationQueue)
    }
    
    // MARK: - Public Methods
    func open(withURL urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else {
            Logger.log("Invalid URL", className: "NetworkDataReader")
            return false
        }
        
        Logger.log("Starting download from: \(urlString)", className: "NetworkDataReader")
        
        // 获取缓存文件路径和临时文件路径
        cacheFilePath = cacheManager.getCacheFilePath(for: url)
        tempCacheFilePath = cacheManager.getTempCacheFilePath(for: url)
        
        // 检查本地缓存文件是否存在
        if let cachePath = cacheFilePath,
           cacheManager.fileExists(at: cachePath) {
            Logger.log("Found cached file at: \(cachePath)", className: "NetworkDataReader")
            
            do {
                let cachedData = try cacheManager.loadCachedData(from: cachePath)
                readQueue.sync {
                    self._totalBytesReceived = cachedData.count
                    self.fileSize = Int64(cachedData.count)
                    
                    // 解密数据并添加到缓冲区
                    let decryptedData = self.crypto.decrypt(data: cachedData, offset: 0)
                    self.downloadedBuffer = decryptedData
                }
                
                // 更新进度
                DispatchQueue.main.async {
                    self.onProgressUpdate?(1.0)
                }
                
                Logger.log("Successfully loaded and decrypted cached file", className: "NetworkDataReader")
                return true
            } catch {
                Logger.log("Failed to read cached file: \(error)", className: "NetworkDataReader")
            }
        }
        
        // 如果没有缓存文件或读取失败，开始下载
        await withCheckedContinuation { continuation in
            downloadQueue.async {
                self.readQueue.sync {
                    self.downloadedBuffer.removeAll()
                    self._currentPosition = 0
                    self._totalBytesReceived = 0
                }
                self.isDownloading = true
                self.retryCount = 0
                continuation.resume()
            }
        }
        
        return await startDownload(url: url)
    }
    
    private func startDownload(url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        await withCheckedContinuation { continuation in
            downloadQueue.async {
                if self._totalBytesReceived > 0 {
                    request.setValue("bytes=\(self._totalBytesReceived)-", forHTTPHeaderField: "Range")
                }
                self.downloadTask = self.session?.dataTask(with: request)
                self.downloadTask?.resume()
                continuation.resume()
            }
        }
        
        // 等待接收到初始数据
        while readQueue.sync(execute: { downloadedBuffer.isEmpty }) && isDownloading {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        
        return readQueue.sync { !downloadedBuffer.isEmpty }
    }
    
    func stop() {
        Logger.log("Stopping NetworkDataReader", className: "NetworkDataReader")
        // 只停止播放，不影响下载
        readQueue.sync {
            isMpkStopped = true
            
            // 通知所有等待的读取操作
            readCondition.lock()
            readCondition.broadcast()
            readCondition.unlock()
            Logger.log("MPK stopped, notifying all waiting operations", className: "NetworkDataReader")
        }
    }
    
    func cleanUp() {
        Logger.log("Cleaning up NetworkDataReader", className: "NetworkDataReader")
        // 先停止下载任务
        downloadQueue.sync {
            self.downloadTask?.cancel()
            self.downloadTask = nil
            self.isDownloading = false
        }
        
        // 设置停止标志
        readQueue.sync {
            isMpkStopped = true
            isDownloading = false
            
            // 通知所有等待的读取操作
            readCondition.lock()
            readCondition.broadcast()
            readCondition.unlock()
            
            // 清理下载的数据
            downloadedBuffer.removeAll()
            _currentPosition = 0
            _totalBytesReceived = 0

            // 清理缓存文件
            if let tempPath = tempCacheFilePath {
                Task {
                    do {
                        // 检查文件是否存在
                        if cacheManager.fileExists(at: tempPath) {
                            try await cacheManager.removeCacheFile(at: tempPath)
                            Logger.log("Successfully removed temp cache file", className: "NetworkDataReader")
                        } else {
                            Logger.log("Temp cache file does not exist, skipping removal", className: "NetworkDataReader")
                        }
                    } catch {
                        Logger.log("Failed to remove temp cache file: \(error)", className: "NetworkDataReader")
                    }
                }
            }
            Logger.log("NetworkDataReader cleaned up", className: "NetworkDataReader")
        }
    }
    
    deinit {
        cleanUp()
        session?.invalidateAndCancel()
        session = nil
        Logger.log("NetworkDataReader deinit", className: "NetworkDataReader")
    }
    
    // MARK: - Media Player Callbacks
    func onRead(_ buffer: UnsafeMutablePointer<UInt8>?, length: Int32) -> Int {
        guard let buffer = buffer else {
            Logger.log("Invalid buffer pointer", className: "NetworkDataReader")
            return 0
        }

        Logger.log("onRead called, length: \(length)", className: "NetworkDataReader")
        
        // 获取当前状态
        let (availableBytes, isDownloading) = readQueue.sync {
            let available = downloadedBuffer.count - _currentPosition
            Logger.log("Available bytes: \(available), requested: \(length), current position: \(_currentPosition), buffer size: \(downloadedBuffer.count)", className: "NetworkDataReader")
            return (available, self.isDownloading)
        }
        
        // 如果 MPK 已停止，直接返回 0
        if isMpkStopped {
            Logger.log("MPK stopped, returning 0", className: "NetworkDataReader")
            return 0
        }
        
        // 如果没有足够的数据且下载还在进行，等待
        if availableBytes < Int(length) && isDownloading {
            Logger.log("Waiting for more data...", className: "NetworkDataReader")
            
            // 等待直到有足够的数据或下载完成
            while availableBytes < Int(length) && isDownloading && !isMpkStopped {
                // 在等待前记录当前状态
                let (currentBufferSize, currentPosition) = readQueue.sync {
                    (downloadedBuffer.count, _currentPosition)
                }
                
                readCondition.lock()
                readCondition.wait(until: Date(timeIntervalSinceNow: 1.0))
                readCondition.unlock()
                
                // 重新获取状态
                let (newAvailableBytes, newIsDownloading) = readQueue.sync {
                    let available = downloadedBuffer.count - _currentPosition
                    return (available, self.isDownloading)
                }
                
                // 只有在缓冲区大小或位置发生变化时才打印日志
                if currentBufferSize != downloadedBuffer.count || currentPosition != _currentPosition {
                    Logger.log("Buffer updated - Size: \(downloadedBuffer.count), Position: \(_currentPosition), Available: \(newAvailableBytes)", className: "NetworkDataReader")
                }
                
                if newAvailableBytes >= Int(length) {
                    break
                }
                
                // 如果 MPK 已经停止，不再等待
                if isMpkStopped {
                    Logger.log("MPK stopped, no more waiting", className: "NetworkDataReader")
                    break
                }
            }
            
            // 如果下载已完成但仍然没有足够数据，返回0
            if !isDownloading && availableBytes < Int(length) {
                Logger.log("Download completed but not enough data available", className: "NetworkDataReader")
                return 0
            }
        }
        
        // 如果 MPK 已停止，直接返回 0
        if isMpkStopped {
            Logger.log("MPK stopped, returning 0", className: "NetworkDataReader")
            return 0
        }
        
        // 重新获取最新的可用字节数
        let finalAvailableBytes = readQueue.sync {
            downloadedBuffer.count - _currentPosition
        }
        
        // 计算实际可以返回的数据长度
        let bytesToReturn = min(Int(length), finalAvailableBytes)
        
        // 复制数据到播放器的缓冲区
        readQueue.sync {
            let range = _currentPosition..<(_currentPosition + bytesToReturn)
            Logger.log("Copying bytes - Current position: \(_currentPosition), Bytes to return: \(bytesToReturn), Range: \(range), Buffer size: \(downloadedBuffer.count)", className: "NetworkDataReader")
            
            // 确保范围有效
            guard range.lowerBound >= 0,
                  range.upperBound <= downloadedBuffer.count else {
                Logger.log("Invalid range: \(range) for buffer size: \(downloadedBuffer.count)", className: "NetworkDataReader")
                return
            }

            downloadedBuffer.withUnsafeBytes { sourceBytes in
                guard let sourcePtr = sourceBytes.baseAddress else {
                    Logger.log("Failed to get source buffer pointer", className: "NetworkDataReader")
                    return
                }
                
                // 计算源数据的起始位置并转换为正确的指针类型
                let sourceStart = sourcePtr.advanced(by: _currentPosition).assumingMemoryBound(to: UInt8.self)
                buffer.assign(from: sourceStart, count: bytesToReturn)
            }
            
            _currentPosition += bytesToReturn
            Logger.log("Returned \(bytesToReturn) bytes", className: "NetworkDataReader")
        }
        
        return bytesToReturn
    }
    
    func onSeek(_ offset: Int64, whence: Int32) -> Int64 {
        Logger.log("onSeek called, offset: \(offset), whence: \(whence)", className: "NetworkDataReader")
        
        // 获取当前状态
        let (currentPosition, bufferSize, isDownloading, isStopped) = readQueue.sync {
            (_currentPosition, downloadedBuffer.count, self.isDownloading, self.isMpkStopped)
        }
        
        // 计算目标位置
        let targetPosition: Int64
        switch whence {
            case 65536:  // AVSEEK_SIZE: 返回文件大小
                Logger.log("[SEEK_SIZE] Getting file size", className: "NetworkDataReader")
                if fileSize > 0 {
                    targetPosition = isEncrypted ? fileSize - Int64(crypto.getHeaderSize()) : fileSize
                } else if !isDownloading {
                    targetPosition = Int64(isEncrypted ? _totalBytesReceived - crypto.getHeaderSize() : _totalBytesReceived)
                } else {
                    return -1
                }
                return targetPosition
                
            case SEEK_SET:
                Logger.log("[SEEK_SET] Attempting to seek to position: \(offset)", className: "NetworkDataReader")
                targetPosition = offset
                
            case SEEK_CUR:
                Logger.log("[SEEK_CUR] Attempting to seek from current position \(currentPosition) by offset: \(offset)", className: "NetworkDataReader")
                targetPosition = Int64(currentPosition) + offset
                
            case SEEK_END:
                Logger.log("[SEEK_END] Attempting to seek to end", className: "NetworkDataReader")
                if fileSize > 0 {
                    targetPosition = fileSize - (isEncrypted ? Int64(crypto.getHeaderSize()) : 0)
                } else if !isDownloading {
                    targetPosition = Int64(_totalBytesReceived - (isEncrypted ? crypto.getHeaderSize() : 0))
                } else {
                    return -1
                }
                
            default:
                Logger.log("[UNKNOWN] Unknown seek whence value: \(whence)", className: "NetworkDataReader")
                return -1
        }
        
        // 确保目标位置不为负
        if targetPosition < 0 {
            Logger.log("Invalid target position: \(targetPosition)", className: "NetworkDataReader")
            return -1
        }
        
        // 等待数据下载直到目标位置可用
        var currentBufferSize = bufferSize
        while Int(targetPosition) > currentBufferSize && isDownloading && !isStopped {
            Logger.log("Position \(targetPosition) beyond buffer size \(currentBufferSize), waiting for data...", className: "NetworkDataReader")
            
            // 等待新数据到达
            readCondition.lock()
            readCondition.wait(until: Date(timeIntervalSinceNow: 1.0))
            readCondition.unlock()
            
            // 更新当前buffer大小
            currentBufferSize = readQueue.sync { downloadedBuffer.count }
            
            // 如果buffer大小没有变化，说明没有新数据到达
            if currentBufferSize == readQueue.sync(execute: { downloadedBuffer.count }) {
                Logger.log("No new data received, current buffer size: \(currentBufferSize), continuing to wait...", className: "NetworkDataReader")
                continue
            }
        }
        
        // 如果下载完成但位置仍然超出，说明请求的位置超出了文件大小
        if Int(targetPosition) > currentBufferSize {
            Logger.log("Failed: requested position \(targetPosition) beyond file size \(currentBufferSize)", className: "NetworkDataReader")
            return -1
        }
        
        // 更新位置
        readQueue.sync { _currentPosition = Int(targetPosition) }
        
        let finalPosition = readQueue.sync { _currentPosition }
        let finalBufferSize = readQueue.sync { downloadedBuffer.count }
        Logger.log("Seek result: \(targetPosition), current position: \(finalPosition), buffer size: \(finalBufferSize)", className: "NetworkDataReader")
        
        return targetPosition
    }
    
    // MARK: - URLSessionDataDelegate
    func urlSession(_ session: URLSession,
                   dataTask: URLSessionDataTask,
                   didReceive data: Data) {
        downloadQueue.async {
            // 在readQueue中同步更新数据
            self.readQueue.sync {
                // 解密数据用于播放
                let decryptedData = self.crypto.decrypt(data: data, offset: self._totalBytesReceived)
                
                // 更新总接收字节数，包含头部大小
                self._totalBytesReceived += data.count
                self.downloadedBuffer.append(decryptedData)
                
                // 通知等待的读取操作有新数据可用
                self.readCondition.lock()
                self.readCondition.broadcast()
                self.readCondition.unlock()
                
                Logger.log("Updated buffer - Total received: \(self._totalBytesReceived), Buffer size: \(self.downloadedBuffer.count)", className: "NetworkDataReader")

                if let tempPath = self.tempCacheFilePath {
                    do {
                        // 检查是否是第一个数据块
                        let isFirstChunk = data.count == self._totalBytesReceived
                        Logger.log("Saving chunk to temp cache - Size: \(data.count), Is first chunk: \(isFirstChunk), Total received: \(self._totalBytesReceived)", className: "NetworkDataReader")
                        try self.cacheManager.saveEncryptedData(data, to: tempPath, isFirstChunk: isFirstChunk)
                    } catch {
                        Logger.log("Failed to save encrypted data to temp cache: \(error)", className: "NetworkDataReader")
                    }
                }
            }
            
            // 更新进度
            if self.fileSize > 0 {
                let progress = Float(self._totalBytesReceived) / Float(self.fileSize)
                DispatchQueue.main.async {
                    self.onProgressUpdate?(progress)
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession,
                   dataTask: URLSessionDataTask,
                   didReceive response: URLResponse,
                   completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        downloadQueue.async {
            if let httpResponse = response as? HTTPURLResponse {
                Logger.log("Received response with status code: \(httpResponse.statusCode)", className: "NetworkDataReader")
                self.fileSize = response.expectedContentLength
                Logger.log("Expected content length: \(self.fileSize)", className: "NetworkDataReader")
                Logger.log("Content type: \(response.mimeType ?? "unknown")", className: "NetworkDataReader")
                
                // 初始化进度为0
                DispatchQueue.main.async {
                    self.onProgressUpdate?(0)
                }
            }
            completionHandler(.allow)
        }
    }
    
    func urlSession(_ session: URLSession,
                   task: URLSessionTask,
                   didCompleteWithError error: Error?) {
        downloadQueue.async {
            Logger.log("Session task completed", className: "NetworkDataReader")
            if let error = error {
                Logger.log("Download error: \(error)", className: "NetworkDataReader")
                
                if (error as NSError).code == NSURLErrorTimedOut && self.retryCount < self.maxRetries {
                    self.retryCount += 1
                    Logger.log("Retrying download (attempt \(self.retryCount) of \(self.maxRetries))", className: "NetworkDataReader")
                    
                    Task {
                        guard let url = task.originalRequest?.url else { return }
                        self.isDownloading = true
                        _ = await self.startDownload(url: url)
                    }
                    return
                }
                
                // 设置下载状态为停止并通知等待的读取操作
                self.readQueue.sync {
                    self.isDownloading = false
                    self.readCondition.lock()
                    self.readCondition.broadcast()
                    self.readCondition.unlock()
                }
                
                // 只在下载出错时删除临时缓存文件
                if let tempPath = self.tempCacheFilePath {
                    Task {
                        do {
                            if self.cacheManager.fileExists(at: tempPath) {
                                try await self.cacheManager.removeCacheFile(at: tempPath)
                            } else {
                                Logger.log("Temp cache file does not exist, skipping removal", className: "NetworkDataReader")
                            }
                        } catch {
                            Logger.log("Failed to clear temp cache file: \(error)", className: "NetworkDataReader")
                        }
                    }
                }
            } else {
                Logger.log("Download completed successfully - Received: \(self._totalBytesReceived) bytes", className: "NetworkDataReader")
                
                // 下载成功，将临时文件重命名为最终文件
                if let tempPath = self.tempCacheFilePath,
                   let finalPath = self.cacheFilePath {
                    Task {
                        do {
                            try await self.cacheManager.moveTempFile(from: tempPath, to: finalPath)
                            Logger.log("Successfully moved temp file to final location: \(finalPath)", className: "NetworkDataReader")
                        } catch {
                            Logger.log("Failed to move temp file to final location: \(error)", className: "NetworkDataReader")
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self.onProgressUpdate?(1)
                }
            }
            
            self.isDownloading = false
        }
    }
}

