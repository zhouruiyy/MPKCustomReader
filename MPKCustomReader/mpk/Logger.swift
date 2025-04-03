import Foundation

enum Logger {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"  // 修改为包含毫秒的格式
        return formatter
    }()
    
    static func log(_ message: String, className: String) {
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] [\(className)] \(message)")
    }
} 