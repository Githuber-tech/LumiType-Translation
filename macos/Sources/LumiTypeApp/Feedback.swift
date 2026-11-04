import AppKit
import LumiTypeCore

/// 用户反馈：本地存档 + 联网提交。
///
/// 存档结构照原版：`feedback/FB-yyyyMMdd-HHmmss/` 内含
/// `反馈内容.txt`、附件原件、`附件清单.txt`。
/// 关键约定：**发送失败也一定先存档**，不让用户写的东西丢。
enum FeedbackStore {

    struct Entry {
        let directory: URL
        let attachmentCount: Int
        let summary: String
        let stamp: String
    }

    static let allowedExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "gif", "bmp", "pdf"]
    static let maxAttachmentBytes = 20 * 1024 * 1024

    static func entries() -> [Entry] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: AppPaths.feedback,
                                                     includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles]) else { return [] }
        return dirs.compactMap { url -> Entry? in
            guard url.lastPathComponent.hasPrefix("FB-") else { return nil }
            let files = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            let attachments = files.filter {
                !$0.lastPathComponent.hasSuffix(".txt")
            }.count
            let bodyURL = url.appendingPathComponent("反馈内容.txt")
            let body = (try? String(contentsOf: bodyURL, encoding: .utf8)) ?? ""
            let summary = body.split(separator: "\n").first.map(String.init) ?? ""
            return Entry(directory: url,
                         attachmentCount: attachments,
                         summary: String(summary.prefix(60)),
                         stamp: url.lastPathComponent.replacingOccurrences(of: "FB-", with: ""))
        }.sorted { $0.stamp > $1.stamp }
    }

    struct ArchiveResult {
        let directory: URL
    }

    static func archive(text: String, attachments: [URL]) throws -> URL {
        let stamp = timestamp()
        let dir = AppPaths.feedback.appendingPathComponent("FB-\(stamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let body = text.isEmpty ? "（未填写内容）" : text
        try body.write(to: dir.appendingPathComponent("反馈内容.txt"), atomically: true, encoding: .utf8)

        var manifest: [String] = []
        for (index, file) in attachments.enumerated() {
            let name = "附件\(index + 1)-\(file.lastPathComponent)"
            try? FileManager.default.copyItem(at: file, to: dir.appendingPathComponent(name))
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
            manifest.append("\(name)\t\(size) bytes")
        }
        let head = "LumiType \(Product.versionText) / macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        try (head + "\n" + manifest.joined(separator: "\n"))
            .write(to: dir.appendingPathComponent("附件清单.txt"), atomically: true, encoding: .utf8)
        return dir
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    /// multipart/form-data 提交。成功回调 nil，失败回调错误文案。
    static func send(text: String, attachments: [URL], archivedAt dir: URL,
                     completion: @escaping (String?) -> Void) {
        let endpoint = ConfigStore.shared.config.feedbackEndpoint
        guard !endpoint.isEmpty, let url = URL(string: endpoint) else {
            completion(nil)   // 端点置空 = 仅本地保存，不算失败
            return
        }
        let boundary = "LumiType-\(UUID().uuidString)"
        var body = Data()

        func append(_ string: String) {
            body.append(string.data(using: .utf8) ?? Data())
        }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append(value + "\r\n")
        }

        field("_subject", "LumiType 用户反馈")
        field("版本", Product.versionText)
        field("平台", "macOS")
        field("内容", text.isEmpty ? "（未填写内容）" : text)
        field("存档目录", dir.lastPathComponent)

        for (index, file) in attachments.enumerated() {
            guard let data = try? Data(contentsOf: file) else { continue }
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"附件\(index + 1)\"; filename=\"\(file.lastPathComponent)\"\r\n")
            append("Content-Type: \(mime(for: file))\r\n\r\n")
            body.append(data)
            append("\r\n")
        }
        append("--\(boundary)--\r\n")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(Product.repositoryURL, forHTTPHeaderField: "Referer")
        request.setValue("LumiType/\(Product.versionText) (macOS)", forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                DispatchQueue.main.async { completion(error.localizedDescription) }
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                DispatchQueue.main.async { completion("HTTP \(http.statusCode) \(body.prefix(120))") }
                return
            }
            DispatchQueue.main.async { completion(nil) }
        }.resume()
    }

    private static func mime(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "bmp": return "image/bmp"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - 反馈页（首选项第 4 页）

/// 上报页面容器：flipped 坐标系 + 布局回调，避免 Auto Layout 在 NSTabView 里
/// 拿不到稳定尺寸（实测：给页面 view 关掉 autoresizing 后整块内容会被压成零高）。
final class PageLayoutView: NSView {
    override var isFlipped: Bool { true }
    var onLayout: (() -> Void)?
    override func layout() {
        super.layout()
        onLayout?()
    }
}

final class FeedbackPage: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    let view: PageLayoutView
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let desc = NSTextField(labelWithString: "")
    private let writeButton = NSButton()
    private let openButton = NSButton()
    private var rows: [FeedbackStore.Entry] = []

    override init() {
        view = PageLayoutView(frame: NSRect(x: 0, y: 0, width: 640, height: 700))
        super.init()
        build()
        reload()
        view.onLayout = { [weak self] in self?.layoutContent() }
    }

    private func layoutContent() {
        let w = view.bounds.width, h = view.bounds.height
        let pad: CGFloat = 16
        let contentW = w - pad * 2
        let descH = max(18, desc.sizeThatFits(NSSize(width: contentW, height: 400)).height)
        desc.frame = NSRect(x: pad, y: 14, width: contentW, height: descH)
        let buttonY = h - 16 - 26
        scroll.frame = NSRect(x: pad, y: desc.frame.maxY + 12,
                              width: contentW, height: max(80, buttonY - 12 - (desc.frame.maxY + 12)))
        writeButton.frame = NSRect(x: pad, y: buttonY, width: writeButton.frame.width, height: 26)
        openButton.frame = NSRect(x: writeButton.frame.maxX + 10, y: buttonY,
                                  width: openButton.frame.width, height: 26)
        emptyLabel.frame = NSRect(x: 0, y: 20, width: scroll.contentView.bounds.width, height: 18)
        emptyLabel.alignment = .center
    }

    private let emptyLabel = NSTextField(labelWithString: "")

    private func build() {
        let store = ConfigStore.shared

        desc.stringValue = store.t("fb_desc_mac")
        desc.font = NSFont.systemFont(ofSize: 11)
        desc.textColor = .secondaryLabelColor
        desc.lineBreakMode = .byWordWrapping
        desc.maximumNumberOfLines = 0
        view.addSubview(desc)

        let columns: [(String, String, CGFloat)] = [
            ("dir", store.t("fb_col_dir"), 230),
            ("att", store.t("fb_col_att"), 60),
            ("sum", store.t("fb_col_sum"), 250),
            ("open", "", 48)
        ]
        for (id, title, width) in columns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            table.addTableColumn(col)
        }
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 22
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        scroll.hasVerticalScroller = true
        scroll.documentView = table
        scroll.borderType = .bezelBorder
        view.addSubview(scroll)

        emptyLabel.stringValue = store.t("fb_empty")
        emptyLabel.font = NSFont.systemFont(ofSize: 11)
        emptyLabel.textColor = .tertiaryLabelColor
        scroll.addSubview(emptyLabel)

        writeButton.title = store.t("fb_write")
        writeButton.bezelStyle = .rounded
        writeButton.font = NSFont.systemFont(ofSize: 12)
        writeButton.target = self
        writeButton.action = #selector(writeFeedback)
        writeButton.sizeToFit()
        view.addSubview(writeButton)

        openButton.title = store.t("fb_opendir")
        openButton.bezelStyle = .rounded
        openButton.font = NSFont.systemFont(ofSize: 12)
        openButton.target = self
        openButton.action = #selector(openFolder)
        openButton.sizeToFit()
        view.addSubview(openButton)
    }

    private func reload() {
        rows = FeedbackStore.entries()
        table.reloadData()
        emptyLabel.isHidden = !rows.isEmpty
        table.usesAlternatingRowBackgroundColors = !rows.isEmpty
    }

    @objc private func writeFeedback() {
        FeedbackEditorController.present { [weak self] in
            self?.reload()
        }
    }

    @objc private func openFolder() {
        AppPaths.ensure(AppPaths.feedback)
        NSWorkspace.shared.open(AppPaths.feedback)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn, row < rows.count else { return nil }
        let entry = rows[row]
        if column.identifier.rawValue == "open" {
            let button = NSButton(title: "↗", target: self, action: #selector(openRow(_:)))
            button.tag = row
            button.isBordered = false
            return button
        }
        let text: String
        switch column.identifier.rawValue {
        case "dir": text = entry.directory.lastPathComponent
        case "att": text = "\(entry.attachmentCount)"
        default: text = entry.summary
        }
        let cell = NSTableCellView()
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: 11)
        field.lineBreakMode = .byTruncatingTail
        field.frame = NSRect(x: 4, y: 3, width: column.width - 8, height: 18)
        cell.addSubview(field)
        return cell
    }

    @objc private func openRow(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < rows.count else { return }
        NSWorkspace.shared.open(rows[sender.tag].directory)
    }
}

// MARK: - 写反馈窗口

final class FeedbackEditorController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    private static var active: FeedbackEditorController?

    private let textView = NSTextView()
    private let table = NSTableView()
    private var attachments: [URL] = []
    private var onClose: (() -> Void)?

    static func present(onClose: (() -> Void)? = nil) {
        let controller = FeedbackEditorController()
        controller.onClose = onClose
        active = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = ConfigStore.shared.t("fb_title")
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        build()
    }

    private func build() {
        guard let content = window?.contentView else { return }
        let store = ConfigStore.shared

        let title = Controls.label(store.t("fb_label"), size: 12, bold: true)
        title.frame = NSRect(x: 20, y: 480, width: 520, height: 18)
        content.addSubview(title)

        textView.frame = NSRect(x: 20, y: 300, width: 520, height: 170)
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 12)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 300, width: 520, height: 170))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = textView
        content.addSubview(scroll)

        let attTitle = Controls.label(store.t("fb_att_group"), size: 12, bold: true)
        attTitle.frame = NSRect(x: 20, y: 270, width: 520, height: 18)
        content.addSubview(attTitle)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        col.title = store.t("fb_col_name")
        col.width = 400
        table.addTableColumn(col)
        let col2 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        col2.title = store.t("fb_col_size")
        col2.width = 100
        table.addTableColumn(col2)
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 22

        let tableScroll = NSScrollView(frame: NSRect(x: 20, y: 160, width: 520, height: 100))
        tableScroll.hasVerticalScroller = true
        tableScroll.borderType = .bezelBorder
        tableScroll.documentView = table
        content.addSubview(tableScroll)

        let add = Controls.button(store.t("fb_add"), target: self, action: #selector(addAttachments))
        add.frame.origin = NSPoint(x: 20, y: 122)
        content.addSubview(add)

        let remove = Controls.button(store.t("fb_del"), target: self, action: #selector(removeAttachment))
        remove.frame.origin = NSPoint(x: 20 + add.frame.width + 8, y: 122)
        content.addSubview(remove)

        let send = Controls.button(store.t("fb_send"), target: self, action: #selector(send))
        send.frame.origin = NSPoint(x: 440, y: 24)
        content.addSubview(send)

        let cancel = Controls.button(store.t("fb_cancel"), target: self, action: #selector(cancel))
        cancel.frame.origin = NSPoint(x: 360, y: 24)
        content.addSubview(cancel)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { attachments.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < attachments.count, let column = tableColumn else { return nil }
        let url = attachments[row]
        let text: String
        if column.identifier.rawValue == "size" {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            text = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        } else {
            text = url.lastPathComponent
        }
        let cell = NSTableCellView()
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: 11)
        field.lineBreakMode = .byTruncatingMiddle
        field.frame = NSRect(x: 4, y: 2, width: column.width - 8, height: 18)
        cell.addSubview(field)
        return cell
    }

    @objc private func addAttachments() {
        let panel = NSOpenPanel()
        panel.title = ConfigStore.shared.t("fb_pick_title")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedFileTypes = Array(FeedbackStore.allowedExtensions)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let ext = url.pathExtension.lowercased()
            guard FeedbackStore.allowedExtensions.contains(ext) else {
                alert(ConfigStore.shared.t("fb_err_type", [url.lastPathComponent]))
                continue
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            guard size <= FeedbackStore.maxAttachmentBytes else {
                alert(ConfigStore.shared.t("fb_err_big", [url.lastPathComponent]))
                continue
            }
            attachments.append(url)
        }
        table.reloadData()
    }

    @objc private func removeAttachment() {
        let row = table.selectedRow
        guard row >= 0, row < attachments.count else { return }
        attachments.remove(at: row)
        table.reloadData()
    }

    @objc private func send() {
        let store = ConfigStore.shared
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else {
            alert(store.t("fb_err_empty"))
            return
        }
        do {
            let dir = try FeedbackStore.archive(text: text, attachments: attachments)
            FeedbackStore.send(text: text, attachments: attachments, archivedAt: dir) { [weak self] error in
                guard let self else { return }
                if let error {
                    self.alert(store.t("fb_send_fail2", [error]) + "\n" + dir.path)
                } else {
                    self.alert(store.t("fb_send_ok") + "\n" + dir.lastPathComponent)
                }
                self.close()
                self.onClose?()
            }
        } catch {
            alert(store.t("fb_err_save", [error.localizedDescription]))
        }
    }

    @objc private func cancel() {
        close()
    }

    private func alert(_ text: String) {
        let a = NSAlert()
        a.messageText = text
        a.alertStyle = .informational
        a.runModal()
    }

    override func close() {
        super.close()
        FeedbackEditorController.active = nil
    }
}
