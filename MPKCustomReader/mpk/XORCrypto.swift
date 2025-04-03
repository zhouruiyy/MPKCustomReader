import Foundation

class XORCrypto {
    private let key: [UInt8]
    
    init(key: [UInt8] = [0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0]) {
        self.key = key
    }
    
    // MARK: - File Operations
    
    /// 加密文件
    /// - Parameters:
    ///   - sourceURL: 源文件路径
    ///   - destinationURL: 目标文件路径
    /// - Throws: 文件操作错误
    func encryptFile(at sourceURL: URL, to destinationURL: URL) throws {
        // 读取源文件
        let sourceData = try Data(contentsOf: sourceURL)
        
        // 加密数据
        let encryptedData = try encrypt(data: sourceData)
        
        // 写入目标文件
        try encryptedData.write(to: destinationURL, options: .atomic)
        
        Logger.log("Successfully encrypted file from \(sourceURL) to \(destinationURL)", className: "XORCrypto")
    }

    // MARK: - Data Operations
    
    func encrypt(data: Data) throws -> Data {
        let header = CryptoHeader(fileSize: UInt64(data.count))
        var encryptedData = header.serialize()
        
        let allData = encryptedData + data
        let encrypted = allData.enumerated().map { index, byte in
            byte ^ key[index % key.count]
        }

        return Data(bytes: encrypted, count: encrypted.count)
    }
    
    func decrypt(data: Data, offset: Int) -> Data {
        if offset == 0 {
            // 先解密整个数据
            let decrypted = data.enumerated().map { index, byte in
                byte ^ key[index % key.count]
            }
            
            // 验证header
            let decryptedData = Data(bytes: decrypted, count: decrypted.count)
            guard decryptedData.count >= CryptoHeader.headerSize,
                  let header = CryptoHeader(data: decryptedData) else {
                return data
            }
            
            // 去掉header，返回实际数据
            return decryptedData.dropFirst(CryptoHeader.headerSize)
        } else {
            // 处理流式解密
            return Data(data.enumerated().map { index, byte in
                byte ^ key[(offset + index) % key.count]
            })
        }
    }
    
    func getHeaderSize() -> Int {
        return CryptoHeader.headerSize
    }
} 
