import Foundation
import AgoraRtcKit

class CustomDataReader {
    private var fileDescriptor: Int32 = -1
    private var fileSize: Int64 = 0
    
    func open(withFileName path: String) -> Bool {
        fileDescriptor = Darwin.open(path, O_RDONLY)
        if fileDescriptor == -1 {
            Logger.log("Failed to open file", className: "CustomDataReader")
            return false
        }
        
        var stat = Darwin.stat()
        if Darwin.fstat(fileDescriptor, &stat) == 0 {
            fileSize = Int64(stat.st_size)
        } else {
            Logger.log("Failed to get file size", className: "CustomDataReader")
            Darwin.close(fileDescriptor)
            fileDescriptor = -1
            return false
        }
        
        return true
    }
    
    func onRead(_ buffer: UnsafeMutablePointer<UInt8>?, length: Int32) -> Int {
        guard let buffer = buffer, fileDescriptor != -1 else {
            return 0
        }
        
        return Darwin.read(fileDescriptor, buffer, Int(length))
    }
    
    func onSeek(_ offset: Int64, whence: Int32) -> Int64 {
        guard fileDescriptor != -1 else { return -1 }
        
        if whence == 65536 {
            return fileSize
        }
        
        if whence == 0 { // SEEK_SET
            return Darwin.lseek(fileDescriptor, offset, SEEK_SET)
        }
        
        return -1
    }
    
    deinit {
        if fileDescriptor != -1 {
            Darwin.close(fileDescriptor)
        }
    }
}

extension CustomDataReader {
    static func setupMediaPlayer(_ mediaPlayer: AgoraRtcMediaPlayerProtocol, withFilePath path: String) -> Bool {
        let dataReader = CustomDataReader()
        guard dataReader.open(withFileName: path) else {
            return false
        }
        
        let source = AgoraMediaSource()
        
        let onReadCallback: AgoraRtcMediaPlayerCustomSourceOnReadCallback = { (player: AgoraRtcMediaPlayerProtocol, buf: UnsafeMutablePointer<UInt8>?, length: Int32) -> Int32 in
            Logger.log("onRead called, requested length: \(length)", className: "CustomDataReader")
            let ret = dataReader.onRead(buf, length: length)
            return Int32(ret)
        }
        
        let onSeekCallback: AgoraRtcMediaPlayerCustomSourceOnSeekCallback = { (player: AgoraRtcMediaPlayerProtocol, offset: Int64, whence: Int32) -> Int64 in
            Logger.log("onSeek called, offset: \(offset), whence: \(whence)", className: "CustomDataReader")
            let ret = dataReader.onSeek(offset, whence: whence)
            return ret
        }
        
        source.playerOnReadCallback = onReadCallback
        source.playerOnSeekCallback = onSeekCallback
        // 将url设置为空字符串，因为我们使用自定义数据源
        source.url = ""
        
        // 打开媒体播放器
        let ret = mediaPlayer.open(with: source)
        return ret == 0
    }
} 
