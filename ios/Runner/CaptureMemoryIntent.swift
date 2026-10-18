import AppIntents
import Flutter
import UIKit

@available(iOS 16.0, *)
struct CaptureMemoryIntent: AppIntent {
    static var title: LocalizedStringResource = "存入 AI 记忆"
    static var description = IntentDescription("接收截图、原生 OCR 文本与备注，静默写入本地记忆队列并触发解析。")
    
    // 核心配置：false 表示在后台静默运行，不打断当前屏幕正在使用的 App
    static var openAppWhenRun: Bool = false

    @Parameter(title: "截图或图片", supportedTypeIdentifiers: ["public.image"])
    var imageFile: IntentFile?

    @Parameter(title: "OCR 提取文本", default: "")
    var ocrText: String

    @Parameter(title: "补充备注", default: "")
    var userNote: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let uuid = UUID().uuidString.lowercased()
        let fileManager = FileManager.default
        guard let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return .result(value: "无法访问沙盒目录")
        }

        let inboxDir = docsDir.appendingPathComponent("pending_inbox", isDirectory: true)
        try? fileManager.createDirectory(at: inboxDir, withIntermediateDirectories: true)

        // 1. 保存图片文件到 pending_inbox/<uuid>.img
        var savedImagePath: String? = nil
        if let file = imageFile, let data = try? file.data {
            let imgURL = inboxDir.appendingPathComponent("\(uuid).img")
            try? data.write(to: imgURL, options: .atomic)
            savedImagePath = imgURL.path
        }

        // 2. 保存元数据 JSON 到 pending_inbox/<uuid>.json（确保即使后台超时也 100% 不丢数据）
        let payload: [String: Any] = [
            "id": uuid,
            "created_at": Int(Date().timeIntervalSince1970 * 1000),
            "image_path": savedImagePath ?? "",
            "ocr_text": ocrText,
            "user_note": userNote,
            "source": "ios_shortcut"
        ]
        let jsonURL = inboxDir.appendingPathComponent("\(uuid).json")
        if let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted) {
            try? jsonData.write(to: jsonURL, options: .atomic)
        }

        // 3. 尝试通知已驻留或后台唤醒的 FlutterEngine 立即处理该条记忆
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
           let controller = appDelegate.window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(name: "com.aimemory.app/inbox", binaryMessenger: controller.binaryMessenger)
            channel.invokeMethod("processInboxItem", arguments: uuid)
            // 留出最大约 4 秒窗口供 Dart 完成轻量 API 请求与本地通知推送
            try? await Task.sleep(nanoseconds: 4_000_000_000)
        }

        return .result(value: "已加入记忆队列：\(uuid)")
    }
}
