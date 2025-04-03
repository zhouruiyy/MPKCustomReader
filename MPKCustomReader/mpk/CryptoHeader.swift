import Foundation

struct CryptoHeader {
    static let magicNumber: UInt32 = 0x4B50474D // "MGPK" in hex
    static let version: UInt32 = 1
    static let headerSize = 16 // 总长度16字节
    
    let magic: UInt32      // 4字节
    let version: UInt32    // 4字节
    let originalSize: UInt64 // 8字节，原始文件大小
    
    init(fileSize: UInt64) {
        self.magic = CryptoHeader.magicNumber
        self.version = CryptoHeader.version
        self.originalSize = fileSize
    }
    
    init?(data: Data) {
        guard data.count >= CryptoHeader.headerSize else { return nil }
        
        magic = data.withUnsafeBytes { bytes in
            let ptr = bytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
            return UInt32(ptr[0]) | (UInt32(ptr[1]) << 8) | (UInt32(ptr[2]) << 16) | (UInt32(ptr[3]) << 24)
        }
        version = data.withUnsafeBytes { bytes in
            let ptr = bytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
            return UInt32(ptr[4]) | (UInt32(ptr[5]) << 8) | (UInt32(ptr[6]) << 16) | (UInt32(ptr[7]) << 24)
        }
        originalSize = data.withUnsafeBytes { bytes in
            let ptr = bytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
            return UInt64(ptr[8]) | (UInt64(ptr[9]) << 8) | (UInt64(ptr[10]) << 16) | (UInt64(ptr[11]) << 24) |
                   (UInt64(ptr[12]) << 32) | (UInt64(ptr[13]) << 40) | (UInt64(ptr[14]) << 48) | (UInt64(ptr[15]) << 56)
        }
        
        guard magic == CryptoHeader.magicNumber else { return nil }
    }
    
    func serialize() -> Data {
        var data = Data(capacity: CryptoHeader.headerSize)
        data.append(contentsOf: withUnsafeBytes(of: magic) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: version) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: originalSize) { Array($0) })
        return data
    }
} 
