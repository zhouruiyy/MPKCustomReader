//
//  ViewController.swift
//  MPKCustomReader
//
//  Created by ZhouRui on 2025/4/3.
//

import UIKit

/// 主页面控制器
/// 提供进入播放器的入口
class ViewController: UIViewController {
    
    // MARK: - UI Components
    
    /// 进入播放器的按钮
    private lazy var enterButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("进入播放器", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        button.setTitleColor(.systemBlue, for: .normal)
        button.backgroundColor = .systemBackground
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.systemBlue.cgColor
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        button.addTarget(self, action: #selector(enterButtonTapped), for: .touchUpInside)
        return button
    }()
    
    // MARK: - Lifecycle Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    // MARK: - Private Methods
    
    /// 设置UI界面
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // 添加按钮到视图
        view.addSubview(enterButton)
        enterButton.translatesAutoresizingMaskIntoConstraints = false
        
        // 设置按钮约束
        NSLayoutConstraint.activate([
            enterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            enterButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    /// 处理按钮点击事件
    /// 创建并展示 MediaPlayerViewController
    @objc private func enterButtonTapped() {
        let mediaPlayerVC = MediaPlayerViewController()
        mediaPlayerVC.modalPresentationStyle = .fullScreen
        present(mediaPlayerVC, animated: true)
    }
}

