import Foundation
import AppKit
import CoreGraphics
import Security

/// 图片附件管理器 — 高性能处理 AI 聊天中的图片输入。
///
/// 职责：
/// 1. 读取本地图片文件并缩放/压缩为 PNG。
/// 2. 调用 macOS 系统截图工具（`screencapture -i`）捕获屏幕区域；先通过 CoreGraphics 检查并申请屏幕录制权限。
/// 3. 将图片转为 base64 data URL，对齐 Hermes 视觉内容格式。
/// 4. 缓存到 `~/.hermes/images/`（与 Hermes CLI 行为一致）。
///
/// 所有 IO / 图像处理 / base64 编码都在后台队列执行，仅通过主线程回调结果。
@MainActor
final class ImageAttachmentManager {

    /// 全局共享实例。
    static let shared = ImageAttachmentManager()

    /// 后台处理队列。
    private let workQueue = DispatchQueue(
        label: "com.deskmate.ImageAttachmentManager",
        qos: .userInitiated
    )

    /// 图片最大边长（像素）。超过此值会等比缩放，控制 base64 体积与传输耗时。
    private let maxPixelSize: CGFloat = 1600

    /// 缓存目录：`~/.hermes/images/`。
    private lazy var cacheDirectory: URL = {
        let home = AppConstants.resolveHermesHome()
        return URL(fileURLWithPath: home).appendingPathComponent("images", isDirectory: true)
    }()

    private init() {}

    // MARK: - Public API

    /// 从本地文件路径加载图片并生成附件。
    ///
    /// - Parameters:
    ///   - url: 本地图片文件 URL。
    ///   - completion: 主线程回调，成功返回 `ChatImageAttachment`。
    func attachImage(from url: URL, completion: @escaping @MainActor (Result<ChatImageAttachment, Error>) -> Void) {
        workQueue.async { [weak self] in
            guard let self = self else { return }
            let result = self.processImageFile(at: url)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// 从 `NSImage`（如剪贴板粘贴）生成附件。
    ///
    /// - Parameters:
    ///   - image: 已加载的 `NSImage`。
    ///   - displayName: UI 显示名；为空时使用时间戳名称。
    ///   - completion: 主线程回调，成功返回 `ChatImageAttachment`。
    func attachImage(
        from image: NSImage,
        displayName: String? = nil,
        completion: @escaping @MainActor (Result<ChatImageAttachment, Error>) -> Void
    ) {
        workQueue.async { [weak self] in
            guard let self = self else { return }
            let result = self.processImage(image, displayName: displayName)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// 调用系统截图工具捕获屏幕区域并生成附件。
    ///
    /// 使用 `screencapture -i` 进入交互式选区模式；用户按 Esc 取消时返回 `cancelled` 错误。
    /// 会先检查屏幕录制权限，未授权时主动申请一次，拒绝则返回 `permissionDenied` 错误。
    /// - Parameter completion: 主线程回调。
    func captureScreenshot(completion: @escaping @MainActor (Result<ChatImageAttachment, Error>) -> Void) {
        workQueue.async { [weak self] in
            guard let self = self else { return }

            guard self.ensureScreenRecordingPermission() else {
                DispatchQueue.main.async {
                    completion(.failure(ImageAttachmentError.permissionDenied))
                }
                return
            }

            let result = self.runInteractiveScreenshot()
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    // MARK: - Private implementation

    /// 处理本地图片：加载 → 缩放 → PNG → 缓存 → base64。
    private func processImageFile(at url: URL) -> Result<ChatImageAttachment, Error> {
        guard let image = NSImage(contentsOf: url) else {
            return .failure(ImageAttachmentError.loadFailed("无法读取图片：\(url.lastPathComponent)"))
        }
        return processImage(image, displayName: url.lastPathComponent)
    }

    /// 处理 `NSImage`：缩放 → PNG → 缓存 → base64。
    private func processImage(_ image: NSImage, displayName: String? = nil) -> Result<ChatImageAttachment, Error> {
        guard let data = self.preparePngData(from: image) else {
            return .failure(ImageAttachmentError.encodeFailed("图片压缩/编码失败"))
        }

        let name = displayName ?? "paste_\(Int(Date().timeIntervalSince1970))"
        do {
            let cacheURL = try self.saveToCache(data: data, displayName: name)
            let attachment = ChatImageAttachment(
                id: UUID().uuidString,
                dataUrl: "data:image/png;base64,\(data.base64EncodedString())",
                localPath: cacheURL.path,
                displayName: cacheURL.lastPathComponent
            )
            return .success(attachment)
        } catch {
            return .failure(error)
        }
    }

    /// 执行交互式截图并处理结果。
    private func runInteractiveScreenshot() -> Result<ChatImageAttachment, Error> {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("deskmate_screenshot_\(UUID().uuidString).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i : 交互式区域截图； -x : 不播放截图声音； -o : 不在窗口捕获中包含阴影。
        process.arguments = ["-i", "-x", "-o", tempURL.path]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure(ImageAttachmentError.screenshotFailed("无法启动截图工具：\(error.localizedDescription)"))
        }

        // 用户取消（Esc）时 screencapture 不会创建文件。
        guard FileManager.default.fileExists(atPath: tempURL.path) else {
            return .failure(ImageAttachmentError.cancelled)
        }

        defer {
            // 处理完后删除临时文件；已保存到 ~/.hermes/images/ 的缓存保留。
            try? FileManager.default.removeItem(at: tempURL)
        }

        return processImageFile(at: tempURL)
    }

    /// 检查并申请屏幕录制权限。
    ///
    /// 已授权时直接返回 `true`；未授权时调用系统弹窗申请一次，返回用户是否同意。
    /// 申请返回后会再次检测，以处理用户去系统设置手动开启的场景。
    /// macOS 10.15 以下版本直接视为已授权。
    private nonisolated func ensureScreenRecordingPermission() -> Bool {
        if #available(macOS 10.15, *) {
            let bundleId = Bundle.main.bundleIdentifier ?? "nil"
            let executable = Bundle.main.executablePath ?? "nil"
            DMLogger.log("App identity: bundle=\(bundleId) executable=\(executable)", name: "ImageAttachmentManager")
            logCodeSigningInfo()

            let preflight = CGPreflightScreenCaptureAccess()
            DMLogger.log("Screen capture preflight: \(preflight)", name: "ImageAttachmentManager")
            if preflight {
                return true
            }

            // 在主线程申请权限，避免后台调用导致系统弹窗行为异常。
            var requestResult = false
            DispatchQueue.main.sync {
                requestResult = CGRequestScreenCaptureAccess()
                DMLogger.log("Screen capture request result: \(requestResult)", name: "ImageAttachmentManager")
            }

            // 部分情况下 request 返回 false，但授权已写入 TCC；再检测一次。
            let postCheck = CGPreflightScreenCaptureAccess()
            DMLogger.log("Screen capture post-check: \(postCheck)", name: "ImageAttachmentManager")
            return requestResult || postCheck
        }
        return true
    }

    /// 记录当前应用的代码签名信息，帮助诊断 TCC 权限绑定对象。
    private nonisolated func logCodeSigningInfo() {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(
            Bundle.main.bundleURL as CFURL,
            [],
            &staticCode
        )
        guard createStatus == errSecSuccess, let code = staticCode else {
            DMLogger.log("Code signing info: unable to create static code (status=\(createStatus))", name: "ImageAttachmentManager")
            return
        }

        var signingInfo: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInfo
        )
        guard infoStatus == errSecSuccess, let info = signingInfo as? [String: Any] else {
            DMLogger.log("Code signing info: unable to copy signing info (status=\(infoStatus))", name: "ImageAttachmentManager")
            return
        }

        let identifier = info[kSecCodeInfoIdentifier as String] as? String ?? "nil"
        let teamId = info[kSecCodeInfoTeamIdentifier as String] as? String ?? "nil"
        let signatureFlags = info[kSecCodeInfoFlags as String] as? UInt ?? 0
        DMLogger.log("Code signing info: identifier=\(identifier) team=\(teamId) flags=\(signatureFlags)", name: "ImageAttachmentManager")
    }

    /// 将 NSImage 缩放并按 PNG 编码。
    ///
    /// - 等比缩放，使最长边不超过 `maxPixelSize`。
    /// - 保持 alpha 通道；若原图无 alpha 则使用 RGB。
    private func preparePngData(from image: NSImage) -> Data? {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let scale = min(
            1.0,
            maxPixelSize / max(sourceSize.width, sourceSize.height)
        )
        let targetSize = NSSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        bitmap.size = targetSize

        guard let ctx = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        image.draw(in: NSRect(origin: .zero, size: targetSize))
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }

    /// 将 PNG 数据保存到 `~/.hermes/images/`，文件名带时间戳。
    private func saveToCache(data: Data, displayName: String) throws -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: cacheDirectory.path) {
            try fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let safeName = (displayName as NSString).deletingPathExtension
            .replacingOccurrences(of: "/", with: "-")
        let fileName = "\(timestamp)_\(safeName).png"
        let cacheURL = cacheDirectory.appendingPathComponent(fileName)
        try data.write(to: cacheURL)
        return cacheURL
    }
}

// MARK: - Errors

enum ImageAttachmentError: LocalizedError, Equatable {
    case loadFailed(String)
    case encodeFailed(String)
    case screenshotFailed(String)
    case permissionDenied
    case cancelled

    var errorDescription: String? {
        switch self {
        case .loadFailed(let msg): return msg
        case .encodeFailed(let msg): return msg
        case .screenshotFailed(let msg): return msg
        case .permissionDenied: return "缺少屏幕录制权限。若已开启仍无效，请先在系统设置中移除 DeskMate 的屏幕录制权限，再重启 DeskMate 重新授权。"
        case .cancelled: return "已取消截图"
        }
    }
}
