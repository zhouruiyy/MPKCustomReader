//
//  RtcManager.swift
//  MPKCustromReader
//
//  Created by ZYP on 2023/7/28.
//

import AgoraRtcKit

/// RTC管理器代理协议
/// 用于处理RTC相关的事件回调
protocol RtcManagerDelegate: NSObjectProtocol {
    /// 创建渲染视图的回调
    /// - Parameter view: 需要渲染的视图
    func rtcManagerOnCreatedRenderView(view: UIView)
    
    /// 音频帧捕获的回调
    /// - Parameter frame: 捕获的音频帧
    func rtcManagerOnCaptureAudioFrame(frame: AgoraAudioFrame)
    
    /// 调试信息的回调
    /// - Parameter text: 调试文本
    func rtcManagerOnDebug(text: String)
    
    /// 接收到流消息的回调
    /// - Parameters:
    ///   - userId: 用户ID
    ///   - streamId: 流ID
    ///   - data: 消息数据
    func rtcManagerOnReceiveStreamMessage(userId: UInt, streamId: Int, data: Data)
    
    /// 接收到音频元数据的回调
    /// - Parameters:
    ///   - uid: 用户ID
    ///   - metadata: 元数据
    func rtcManagerOnAudioMetadataReceived(uid: UInt, metadata: Data)
}

/// RTC管理器类
/// 负责处理音视频通话的核心功能
class RtcManager: NSObject {
    // MARK: - Constants
    
    private enum Constants {
        static let appId = "aab8b8f5a8cd4469a63042fcfafe7063"
        static let logTag = "RtcManager"
    }
    
    // MARK: - Properties
    
    /// Agora RTC引擎实例
    public var agoraKit: AgoraRtcEngineKit!
    
    /// RTC管理器代理
    weak var delegate: RtcManagerDelegate?
    
    /// 数据流ID
    public var dataStreamId: Int = 0
    
    /// 远程视频视图
    var removeView: UIView!
    
    // MARK: - Private Properties
    
    /// 是否正在录制
    private var isRecord = false
    
    /// 音频数据队列
    private var soundQueue = Queue<Data>()
    
    // MARK: - Lifecycle
    
    deinit {
        leaveChannel()
        print("\(Constants.logTag): deinit")
    }
    
    // MARK: - Public Methods
    
    /// 初始化RTC引擎
    func initEngine() {
        let config = AgoraRtcEngineConfig()
        config.appId = Constants.appId
        agoraKit = AgoraRtcEngineKit.sharedEngine(with: config, delegate: self)
        
        // 设置频道配置
        agoraKit.setChannelProfile(.liveBroadcasting)
        agoraKit.setClientRole(.broadcaster)
        agoraKit.setAudioScenario(.chorus)
        
        // 启用音视频
        agoraKit.enableVideo()
        agoraKit.enableAudio()
        
        print("\(Constants.logTag): Engine initialized")
    }
    
    /// 加入频道
    /// - Parameter channelId: 频道ID
    func joinChannel(channelId: String) {
        let option = AgoraRtcChannelMediaOptions()
        option.clientRoleType = .broadcaster
        let uid = arc4random() % 100000
        
        let ret = agoraKit.joinChannel(byToken: "",
                                     channelId: channelId,
                                     uid: UInt(uid),
                                     mediaOptions: option) { channel, uid, elapsed in
            print("\(Constants.logTag): Joined channel \(channel) with uid \(uid)")
        }
        
        if ret != 0 {
            print("\(Constants.logTag): Failed to join channel with error code \(ret)")
        }
    }
    
    /// 离开频道
    func leaveChannel() {
        let ret = agoraKit.leaveChannel()
        if ret != 0 {
            print("\(Constants.logTag): Failed to leave channel with error code \(ret)")
        }
    }
    
    /// 开始录制
    func startRecord() {
        isRecord = true
        print("\(Constants.logTag): Recording started")
    }
    
    /// 停止录制
    func stopRecord() {
        isRecord = false
        print("\(Constants.logTag): Recording stopped")
    }
    
    /// 设置播放数据
    /// - Parameter data: 音频数据
    func setPlayData(data: Data) {
        soundQueue.enqueue(data)
    }
    
    /// 设置本地视频视图
    /// - Parameter view: 视频视图
    func setupLocalVideo(view: UIView) {
        let videoCanvas = AgoraRtcVideoCanvas()
        videoCanvas.uid = 0
        videoCanvas.renderMode = .hidden
        videoCanvas.view = view
        agoraKit.setupLocalVideo(videoCanvas)
        print("\(Constants.logTag): Local video setup completed")
    }
    
    /// 设置远程视频视图
    /// - Parameter view: 视频视图
    func setupRemoteVideo(view: UIView) {
        removeView = view
        print("\(Constants.logTag): Remote video view set")
    }
    
    /// 切换摄像头
    func switchCamera() {
        agoraKit.switchCamera()
        print("\(Constants.logTag): Camera switched")
    }
    
    /// 静音本地视频
    /// - Parameter mute: 是否静音
    func muteLocalVideo(mute: Bool) {
        if mute {
            agoraKit.muteLocalVideoStream(true)
            agoraKit.stopPreview()
        } else {
            agoraKit.muteLocalVideoStream(false)
            agoraKit.startPreview()
        }
        print("\(Constants.logTag): Local video \(mute ? "muted" : "unmuted")")
    }
}

// MARK: - AgoraRtcEngineDelegate

extension RtcManager: AgoraRtcEngineDelegate {
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurError errorCode: AgoraErrorCode) {
        print("\(Constants.logTag): RTC engine error occurred with code \(errorCode)")
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        print("\(Constants.logTag): User \(uid) joined the channel")
        
        let videoCanvas = AgoraRtcVideoCanvas()
        videoCanvas.uid = uid
        videoCanvas.renderMode = .hidden
        videoCanvas.view = removeView
        agoraKit.setupRemoteVideo(videoCanvas)
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinChannel channel: String, withUid uid: UInt, elapsed: Int) {
        print("\(Constants.logTag): Joined channel \(channel) with uid \(uid)")
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, receiveStreamMessageFromUid uid: UInt, streamId: Int, data: Data) {
        print("\(Constants.logTag): Received stream message from uid \(uid), streamId \(streamId)")
        delegate?.rtcManagerOnReceiveStreamMessage(userId: uid, streamId: streamId, data: data)
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
        let videoCanvas = AgoraRtcVideoCanvas()
        videoCanvas.uid = uid
        videoCanvas.view = nil
        agoraKit.setupRemoteVideo(videoCanvas)
        print("\(Constants.logTag): User \(uid) went offline with reason \(reason)")
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, audioMetadataReceived uid: UInt, metadata: Data) {
        delegate?.rtcManagerOnAudioMetadataReceived(uid: uid, metadata: metadata)
    }
}

// MARK: - Queue Implementation

/// 线程安全的队列实现
struct Queue<T> {
    private var elements: [T] = []
    private let semaphore = DispatchSemaphore(value: 1)
    private let logTag = "Queue"
    
    /// 入队
    /// - Parameter element: 要入队的元素
    mutating func enqueue(_ element: T) {
        semaphore.wait()
        elements.append(element)
        semaphore.signal()
    }
    
    /// 清空队列
    mutating func reset() {
        semaphore.wait()
        elements.removeAll()
        semaphore.signal()
    }
    
    /// 出队
    /// - Returns: 队首元素，如果队列为空则返回nil
    mutating func dequeue() -> T? {
        semaphore.wait()
        defer { semaphore.signal() }
        return elements.isEmpty ? nil : elements.removeFirst()
    }
    
    /// 查看队首元素
    /// - Returns: 队首元素，如果队列为空则返回nil
    func peek() -> T? {
        semaphore.wait()
        defer { semaphore.signal() }
        return elements.first
    }
    
    /// 检查队列是否为空
    /// - Returns: 是否为空
    func isEmpty() -> Bool {
        semaphore.wait()
        defer { semaphore.signal() }
        return elements.isEmpty
    }
    
    /// 获取队列元素数量
    /// - Returns: 元素数量
    func count() -> Int {
        semaphore.wait()
        defer { semaphore.signal() }
        return elements.count
    }
}

// MARK: - Helper Methods

extension RtcManager {
    /// 在主线程上调用调试回调
    /// - Parameter text: 调试文本
    func invokeRtcManagerOnDebug(text: String) {
        if Thread.isMainThread {
            delegate?.rtcManagerOnDebug(text: text)
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.rtcManagerOnDebug(text: text)
        }
    }
}
