import UIKit
import AgoraRtcKit

class MediaPlayerViewController: UIViewController {
    
    // MARK: - Properties
    private var rtcManager = RtcManager()
    private var mediaPlayer: AgoraRtcMediaPlayerProtocol?
    private var dataReaders: [String: CustomDataReader] = [:]
    private var networkDataReader: NetworkDataReader?
    private var progressUpdateTimer: Timer?
    private var sourceType: SourceType = .network
    private var networkURL: String = ""
    
    private enum SourceType: Int {
        case local = 0
        case network = 1
    }
    
    // MARK: - UI Elements
    private lazy var videoContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var exitButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("退出", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .systemRed
        button.layer.cornerRadius = 8
        button.addTarget(self, action: #selector(exitButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var playButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Play", for: .normal)
        button.addTarget(self, action: #selector(playButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isUserInteractionEnabled = true
        return button
    }()
    
    private lazy var stopButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Stop", for: .normal)
        button.addTarget(self, action: #selector(stopButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isUserInteractionEnabled = true
        return button
    }()
    
    private lazy var forwardButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("+10s", for: .normal)
        button.addTarget(self, action: #selector(forwardButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isUserInteractionEnabled = true
        return button
    }()
    
    private lazy var backwardButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("-5s", for: .normal)
        button.addTarget(self, action: #selector(backwardButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isUserInteractionEnabled = true
        return button
    }()
    
    private lazy var progressSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderTouchEnded(_:)), for: [.touchUpInside, .touchUpOutside])
        slider.translatesAutoresizingMaskIntoConstraints = false
        
        // 设置进度条颜色
        slider.minimumTrackTintColor = .systemBlue // 已播放部分的颜色
        slider.maximumTrackTintColor = .systemGray5 // 未播放部分的颜色
        
        // 确保进度条可以交互
        slider.isUserInteractionEnabled = true
        slider.isEnabled = true
        
        // 设置进度条样式
        let thumbImage = UIImage(systemName: "circle.fill")?.withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
        slider.setThumbImage(thumbImage, for: .normal)
        
        // 设置进度条高度
        slider.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
        
        return slider
    }()
    
    private lazy var downloadProgressView: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.progress = 0
        progressView.progressTintColor = .systemGreen // 已下载部分的颜色
        progressView.trackTintColor = .clear
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.isUserInteractionEnabled = false // 禁用下载进度条的交互
        return progressView
    }()
    
    private lazy var timeLabel: UILabel = {
        let label = UILabel()
        label.text = "00:00 / 00:00"
        label.font = .systemFont(ofSize: 12)
        label.textColor = .darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var downloadProgressLabel: UILabel = {
        let label = UILabel()
        label.text = "下载进度: 0%"
        label.font = .systemFont(ofSize: 12)
        label.textColor = .systemGreen
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var sourceSegmentControl: UISegmentedControl = {
        let items = ["Local File", "Network URL"]
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = 1
        control.addTarget(self, action: #selector(sourceTypeChanged(_:)), for: .valueChanged)
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    private lazy var urlTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Enter MP4 URL"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isHidden = false
        return textField
    }()
    
    private lazy var decryptionSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.isOn = true
        toggle.translatesAutoresizingMaskIntoConstraints = false
        return toggle
    }()
    
    private lazy var decryptionLabel: UILabel = {
        let label = UILabel()
        label.text = "Decrypt Content"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var encryptButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Encrypt Local File", for: .normal)
        button.addTarget(self, action: #selector(encryptButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        rtcManager.initEngine()
        setupUI()
        setupMediaPlayer()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopProgressTimer()
        cleanUp()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .white
        
        // 添加视频容器视图
        view.addSubview(videoContainerView)
        
        // 添加退出按钮
        view.addSubview(exitButton)
        
        let controlStack = UIStackView(arrangedSubviews: [playButton, stopButton, backwardButton, forwardButton])
        controlStack.axis = .horizontal
        controlStack.spacing = 20
        controlStack.translatesAutoresizingMaskIntoConstraints = false
        controlStack.isUserInteractionEnabled = true
        
        // 创建进度条容器视图
        let progressContainer = UIView()
        progressContainer.translatesAutoresizingMaskIntoConstraints = false
        progressContainer.isUserInteractionEnabled = true // 确保容器视图可以接收交互
        
        // 先添加下载进度视图（底层）
        progressContainer.addSubview(downloadProgressView)
        
        // 再添加播放进度条（上层）
        progressContainer.addSubview(progressSlider)
        
        // 设置进度条和下载进度视图的约束
        NSLayoutConstraint.activate([
            progressSlider.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor),
            progressSlider.trailingAnchor.constraint(equalTo: progressContainer.trailingAnchor),
            progressSlider.centerYAnchor.constraint(equalTo: progressContainer.centerYAnchor),
            
            downloadProgressView.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor),
            downloadProgressView.trailingAnchor.constraint(equalTo: progressContainer.trailingAnchor),
            downloadProgressView.centerYAnchor.constraint(equalTo: progressContainer.centerYAnchor)
        ])
        
        // 确保进度条在最上层
        progressContainer.bringSubviewToFront(progressSlider)
        
        let progressStack = UIStackView(arrangedSubviews: [progressContainer, timeLabel, downloadProgressLabel])
        progressStack.axis = .vertical
        progressStack.spacing = 8
        progressStack.translatesAutoresizingMaskIntoConstraints = false
        progressStack.isUserInteractionEnabled = true // 确保堆栈视图可以接收交互
        
        let decryptionStack = UIStackView(arrangedSubviews: [decryptionLabel, decryptionSwitch])
        decryptionStack.axis = .horizontal
        decryptionStack.spacing = 8
        decryptionStack.translatesAutoresizingMaskIntoConstraints = false
        
        let mainStack = UIStackView(arrangedSubviews: [
            videoContainerView,  // 添加视频容器视图到主堆栈
            sourceSegmentControl,
            urlTextField,
            decryptionStack,
            progressStack,
            controlStack,
            encryptButton,
        ])
        mainStack.axis = .vertical
        mainStack.spacing = 20
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            // 设置退出按钮的约束
            exitButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            exitButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            exitButton.widthAnchor.constraint(equalToConstant: 60),
            exitButton.heightAnchor.constraint(equalToConstant: 40),
            
            // 设置视频容器视图的约束
            videoContainerView.heightAnchor.constraint(equalToConstant: 300),
            videoContainerView.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            
            mainStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mainStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            
            progressSlider.widthAnchor.constraint(equalTo: mainStack.widthAnchor)
        ])
    }
    
    private func setupMediaPlayer() {
        // 使用rtcManager的engine创建媒体播放器
        mediaPlayer = rtcManager.agoraKit.createMediaPlayer(with: self)
        // 设置视频播放视图
        mediaPlayer?.setView(videoContainerView)
    }
    
    // MARK: - Actions
    @objc private func playButtonTapped() {
        guard let mediaPlayer = mediaPlayer else { return }
        
        switch sourceType {
        case .local:
            playLocalFile(with: mediaPlayer)
        case .network:
            playNetworkFile(with: mediaPlayer)
        }
    }
    
    @objc private func stopButtonTapped() {
        networkDataReader?.stop()
        mediaPlayer?.stop()
    }
    
    @objc private func sourceTypeChanged(_ sender: UISegmentedControl) {
        sourceType = SourceType(rawValue: sender.selectedSegmentIndex) ?? .local
        urlTextField.isHidden = sourceType == .local
    }
    
    private func playLocalFile(with mediaPlayer: AgoraRtcMediaPlayerProtocol) {
        // 创建自定义数据源
        let source = AgoraMediaSource()
        let dataReader = CustomDataReader()
        
        // 获取本地文件路径
        guard let filePath = Bundle.main.path(forResource: "oceans", ofType: "mp4") else {
            Logger.log("File not found", className: "MediaPlayerViewController")
            return
        }
        
        // 打开文件
        guard dataReader.open(withFileName: filePath) else {
            Logger.log("Failed to open file", className: "MediaPlayerViewController")
            return
        }
        
        // 保存 dataReader 的引用
        dataReaders[String(mediaPlayer.getMediaPlayerId())] = dataReader
        
        // 设置回调
        let onReadCallback: AgoraRtcMediaPlayerCustomSourceOnReadCallback = { [weak self] (player: AgoraRtcMediaPlayerProtocol, buf: UnsafeMutablePointer<UInt8>?, length: Int32) -> Int32 in
            guard let dataReader = self?.dataReaders[String(player.getMediaPlayerId())] else {
                return 0
            }
            Logger.log("onRead called, requested length: \(length)", className: "CustomDataReader")
            let ret = dataReader.onRead(buf, length: length)
            return Int32(ret)
        }
        
        let onSeekCallback: AgoraRtcMediaPlayerCustomSourceOnSeekCallback = { [weak self] (player: AgoraRtcMediaPlayerProtocol, offset: Int64, whence: Int32) -> Int64 in
            guard let dataReader = self?.dataReaders[String(player.getMediaPlayerId())] else {
                return -1
            }
            Logger.log("onSeek called, offset: \(offset), whence: \(whence)", className: "CustomDataReader")
            let ret = dataReader.onSeek(offset, whence: whence)
            return ret
        }
        
        // 配置数据源
        source.playerOnReadCallback = onReadCallback
        source.playerOnSeekCallback = onSeekCallback
        source.url = ""
        
        // 打开并播放媒体
        let ret = mediaPlayer.open(with: source)
        if ret != 0 {
            Logger.log("Failed to open media player: \(ret)", className: "MediaPlayerViewController")
        }
    }
    
    private func playNetworkFile(with mediaPlayer: AgoraRtcMediaPlayerProtocol) {
        let url = "https://github.com/zhouruiyy/TestResource/raw/refs/heads/main/oceans.encrypted.mp4"
        
        Task {
            let success = await setupMediaPlayer(mediaPlayer, 
                                               withURL: url, 
                                               isEncrypted: decryptionSwitch.isOn)
            if !success {
                Logger.log("Failed to setup network media player", className: "MediaPlayerViewController")
            }
        }
    }
    
    private func setupMediaPlayer(_ mediaPlayer: AgoraRtcMediaPlayerProtocol,
                                withURL path: String,
                                isEncrypted: Bool) async -> Bool {
        if let oldReader = networkDataReader {
            oldReader.stop()
            mediaPlayer.stop()
            oldReader.cleanUp()
            networkDataReader = nil
        }
        
        networkDataReader = NetworkDataReader(isEncrypted: isEncrypted)
        guard let dataReader = networkDataReader else { return false }
        
        dataReader.onProgressUpdate = { [weak self] progress in
            self?.updateDownloadProgress(progress)
        }
        guard await dataReader.open(withURL: path) else {
            return false
        }
        
        let source = AgoraMediaSource()
        
        let onReadCallback: AgoraRtcMediaPlayerCustomSourceOnReadCallback = { (player: AgoraRtcMediaPlayerProtocol, buf: UnsafeMutablePointer<UInt8>?, length: Int32) -> Int32 in
            let ret = dataReader.onRead(buf, length: length)
            return Int32(ret)
        }
        
        let onSeekCallback: AgoraRtcMediaPlayerCustomSourceOnSeekCallback = { (player: AgoraRtcMediaPlayerProtocol, offset: Int64, whence: Int32) -> Int64 in
            let ret = dataReader.onSeek(offset, whence: whence)
            return ret
        }
        
        source.playerOnReadCallback = onReadCallback
        source.playerOnSeekCallback = onSeekCallback
        source.url = ""
        
        let ret = mediaPlayer.open(with: source)
        mediaPlayer.selectAudioTrack(0)
        return ret == 0
    }
    
    // MARK: - Progress Control
    private func startProgressTimer() {
        stopProgressTimer()
        DispatchQueue.main.async {
            self.progressUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.updateProgress()
            }
        }
    }
    
    private func stopProgressTimer() {
        progressUpdateTimer?.invalidate()
        progressUpdateTimer = nil
    }
    
    private func updateProgress() {
        guard let mediaPlayer = mediaPlayer else { return }
        let currentPosition = mediaPlayer.getPosition()
        let duration = mediaPlayer.getDuration()
        
        if duration > 0 {
            let progress = Float(currentPosition) / Float(duration)
            let currentTime = formatTime(currentPosition)
            let totalTime = formatTime(duration)
            
            self.progressSlider.value = progress
            self.timeLabel.text = "\(currentTime) / \(totalTime)"
        }
    }
    
    private func formatTime(_ milliseconds: Int) -> String {
        let totalSeconds = milliseconds / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    @objc private func sliderValueChanged(_ slider: UISlider) {
        // 当用户正在拖动时，暂停进度更新
        stopProgressTimer()
        
        // 获取当前下载进度
        let downloadProgress = downloadProgressView.progress
        
        // 如果拖动位置超过已下载区域，限制在已下载区域内
        if slider.value > downloadProgress {
            slider.value = downloadProgress
        }
    }
    
    @objc private func sliderTouchEnded(_ slider: UISlider) {
        guard let mediaPlayer = mediaPlayer else { return }
        let duration = mediaPlayer.getDuration()
        let targetPosition = Int64(Float(duration) * slider.value)
        
        Logger.log("Seeking to position: \(targetPosition)ms (progress: \(slider.value))", className: "MediaPlayerViewController")
        
        // 调用seek
        let seekResult = mediaPlayer.seek(toPosition: Int(targetPosition))
        if seekResult == 0 {
            // 更新当前时间显示
            let currentTime = formatTime(Int(targetPosition))
            let totalTime = formatTime(duration)
            timeLabel.text = "\(currentTime) / \(totalTime)"
            
            // 恢复进度更新
            startProgressTimer()
        } else {
            Logger.log("Seek failed with error code: \(seekResult)", className: "MediaPlayerViewController")
        }
    }
    
    // MARK: - Cleanup
    private func cleanUp() {
        stopProgressTimer()
        dataReaders.removeAll()
        networkDataReader?.cleanUp()
        networkDataReader = nil
        mediaPlayer?.stop()
        rtcManager.agoraKit.destroyMediaPlayer(mediaPlayer)
        mediaPlayer = nil
    }
    
    deinit {
        cleanUp()
        Logger.log("MediaPlayerViewController deinit", className: "MediaPlayerViewController")
    }
    
    // MARK: - Encrypt Button
    @objc private func encryptButtonTapped() {
        // 获取本地文件路径
        guard let filePath = Bundle.main.path(forResource: "oceans", ofType: "mp4") else {
            Logger.log("File not found", className: "MediaPlayerViewController")
            return
        }
        
        let sourceURL = URL(fileURLWithPath: filePath)
        
        do {
            let destinationURL = try encryptVideo(at: sourceURL)
            
            let alert = UIAlertController(
                title: "Success",
                message: "File encrypted successfully.\nSaved to Documents folder: \(destinationURL.lastPathComponent)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
            
        } catch {
            let alert = UIAlertController(
                title: "Error",
                message: "Failed to encrypt file: \(error.localizedDescription)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }
    
    private func encryptVideo(at sourceURL: URL) throws -> URL {
        Logger.log("Encrypting video at: \(sourceURL)", className: "MediaPlayerViewController")
        let keyBytes = key.utf8.map { UInt8($0) }
        let crypto = XORCrypto(key: keyBytes)
        // 获取缓存目录
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let fileName = sourceURL.lastPathComponent
        let encryptedFileName = fileName.replacingOccurrences(of: ".mp4", with: ".encrypted.mp4")
        let destinationURL = cacheDirectory.appendingPathComponent(encryptedFileName)
        try crypto.encryptFile(at: sourceURL, to: destinationURL)
        return destinationURL
    }
    
    // 更新下载进度
    func updateDownloadProgress(_ progress: Float) {
        DispatchQueue.main.async {
            self.downloadProgressView.progress = progress
            let percentage = Int(progress * 100)
            self.downloadProgressLabel.text = "下载进度: \(percentage)%"
        }
    }
    
    @objc private func forwardButtonTapped() {
        guard let mediaPlayer = mediaPlayer else { return }
        let currentPosition = mediaPlayer.getPosition()
        let duration = mediaPlayer.getDuration()
        
        // 获取当前下载进度
        let downloadProgress = downloadProgressView.progress
        
        // 计算目标位置（当前时间 + 10秒）
        var targetPosition = Int64(currentPosition + 10000)
        
        // 确保不超过视频总时长
        targetPosition = min(targetPosition, Int64(duration))
        
        // 计算目标位置的进度
        let targetProgress = Float(targetPosition) / Float(duration)
        
        // 如果目标位置超过已下载区域，限制在已下载区域内
        if targetProgress > downloadProgress {
            targetPosition = Int64(Float(duration) * downloadProgress)
            Logger.log("Target position exceeds download progress, limiting to: \(targetPosition)ms", className: "MediaPlayerViewController")
            return
        }
        
        Logger.log("Seeking forward 10s to position: \(targetPosition)ms", className: "MediaPlayerViewController")
        
        // 调用seek，使用 SEEK_SET (0) 作为 whence 参数
        let seekResult = mediaPlayer.seek(toPosition: Int(targetPosition))
        if seekResult == 0 {
            // 更新当前时间显示
            let currentTime = formatTime(Int(targetPosition))
            let totalTime = formatTime(duration)
            timeLabel.text = "\(currentTime) / \(totalTime)"
            
            // 更新进度条
            let progress = Float(targetPosition) / Float(duration)
            progressSlider.value = progress
            
            // 恢复进度更新
            startProgressTimer()
        } else {
            Logger.log("Seek failed with error code: \(seekResult)", className: "MediaPlayerViewController")
        }
    }
    
    @objc private func backwardButtonTapped() {
        guard let mediaPlayer = mediaPlayer else { return }
        let currentPosition = mediaPlayer.getPosition()
        let duration = mediaPlayer.getDuration()
        
        // 计算目标位置（当前时间 - 5秒）
        var targetPosition = Int64(currentPosition - 5000)
        
        // 确保不小于0
        targetPosition = max(0, targetPosition)
        
        Logger.log("Seeking backward 5s to position: \(targetPosition)ms", className: "MediaPlayerViewController")
        
        // 调用seek
        let seekResult = mediaPlayer.seek(toPosition: Int(targetPosition))
        if seekResult == 0 {
            // 更新当前时间显示
            let currentTime = formatTime(Int(targetPosition))
            let totalTime = formatTime(duration)
            timeLabel.text = "\(currentTime) / \(totalTime)"
            
            // 更新进度条
            let progress = Float(targetPosition) / Float(duration)
            progressSlider.value = progress
            
            // 恢复进度更新
            startProgressTimer()
        } else {
            Logger.log("Seek failed with error code: \(seekResult)", className: "MediaPlayerViewController")
        }
    }
    
    private func handleBufferingState(_ isBuffering: Bool) {
        if isBuffering {
            Logger.log("Buffering started", className: "MediaPlayerViewController")
            mediaPlayer?.pause()
        } else {
            Logger.log("Buffering ended", className: "MediaPlayerViewController")
            mediaPlayer?.play()
        }
    }
    
    @objc private func exitButtonTapped() {
        cleanUp()
        dismiss(animated: true)
    }
}

// MARK: - AgoraRtcMediaPlayerDelegate
extension MediaPlayerViewController: AgoraRtcMediaPlayerDelegate {
    func AgoraRtcMediaPlayer(_ playerKit: any AgoraRtcMediaPlayerProtocol, didChangedTo state: AgoraMediaPlayerState, reason: AgoraMediaPlayerReason) {
        if state == .openCompleted {
            Logger.log("媒体源加载完成，开始播放", className: "MediaPlayerViewController")
            mediaPlayer?.play()
            mediaPlayer?.selectAudioTrack(1)
            startProgressTimer() // 开始进度更新
        } else if state == .stopped || state == .playBackCompleted {
            Logger.log("播放结束，原因: \(state == .stopped ? "手动停止" : "播放完成")", className: "MediaPlayerViewController")
            stopProgressTimer() // 停止进度更新
        } else {
            Logger.log("当前状态: \(state)", className: "MediaPlayerViewController")
        }
    }
}
