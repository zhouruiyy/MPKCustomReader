import Foundation

class CacheManager {
    static let shared = CacheManager()
    
    // 使用串行队列确保文件操作的顺序
    private let fileQueue = DispatchQueue(label: "com.agora.cachemanager.file", qos: .userInitiated)
    
    private init() {}
    
    func getCacheFilePath(for url: URL) -> String {
        let fileName = url.lastPathComponent
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return cacheDir.appendingPathComponent(fileName).path
    }
    
    func getTempCacheFilePath(for url: URL) -> String {
        let fileName = url.lastPathComponent
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let tempFileName = ".temp_\(fileName)"
        return cacheDir.appendingPathComponent(tempFileName).path
    }
    
    func saveEncryptedData(_ data: Data, to path: String, isFirstChunk: Bool) throws {
        fileQueue.async {
            do {
                if isFirstChunk {
                    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
                    Logger.log("Successfully wrote first encrypted chunk to cache: \(path), size: \(data.count)", className: "CacheManager")
                } else {
                    // 确保文件存在
                    if !FileManager.default.fileExists(atPath: path) {
                        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
                        Logger.log("File did not exist, created new file with chunk, size: \(data.count)", className: "CacheManager")
                    } else {
                        // 获取当前文件大小
                        let currentSize = try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64 ?? 0
                        Logger.log("Current file size before append: \(currentSize), appending \(data.count) bytes", className: "CacheManager")
                        
                        // 使用 FileHandle 追加数据
                        let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
                        defer {
                            try? fileHandle.close()
                            fileHandle.closeFile()
                        }
                        
                        // 移动到文件末尾并追加数据
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        try fileHandle.synchronize()
                    }
                }
            } catch {
                Logger.log("Failed to save encrypted data to cache: \(error)", className: "CacheManager")
            }
        }
    }
    
    func loadCachedData(from path: String) throws -> Data {
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }
    
    func removeCacheFile(at path: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            fileQueue.async {
                do {
                    try FileManager.default.removeItem(atPath: path)
                    Logger.log("Cleared cache file: \(path)", className: "CacheManager")
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func fileExists(at path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }
    
    func moveTempFile(from sourcePath: String, to destinationPath: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            fileQueue.async {
                do {
                    // 如果目标文件已存在，先删除
                    if FileManager.default.fileExists(atPath: destinationPath) {
                        try FileManager.default.removeItem(atPath: destinationPath)
                    }
                    
                    // 移动临时文件到目标位置
                    try FileManager.default.moveItem(atPath: sourcePath, toPath: destinationPath)
                    Logger.log("Successfully moved temp file from \(sourcePath) to \(destinationPath)", className: "CacheManager")
                    continuation.resume()
                } catch {
                    Logger.log("Failed to move temp file: \(error)", className: "CacheManager")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    deinit {
        Logger.log("CacheManager deinit", className: "CacheManager")
    }
} 