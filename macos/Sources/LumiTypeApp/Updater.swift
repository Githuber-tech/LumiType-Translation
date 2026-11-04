import AppKit
import CryptoKit
import LumiTypeCore

/// 更新检查与安装。
///
/// 清单格式与 Windows 版完全一致（`latest.json`：version / url / sha256 / notes），
/// 所以仓库里的发布清单不用改；变的只是「怎么落地」：
/// Windows 替换 .exe，macOS 替换 .app 整包。
final class Updater {

    struct Info: Equatable {
        let version: String
        let url: String
        let sha256: String
        let notes: String
    }

    enum UpdateError: LocalizedError {
        case noSource
        case badManifest
        case shaMismatch
        case download(Error)
        case install(String)

        var isNoSource: Bool {
            if case .noSource = self { return true }
            return false
        }

        var isShaMismatch: Bool {
            if case .shaMismatch = self { return true }
            return false
        }

        var errorDescription: String? {
            switch self {
            case .noSource: return "no update source"
            case .badManifest: return "bad manifest"
            case .shaMismatch: return "sha256 mismatch"
            case .download(let e): return e.localizedDescription
            case .install(let s): return s
            }
        }
    }

    var info: Info?

    /// 返回「是否有新版本」；错误通过 completion 抛出，由调用方决定提示方式。
    func check(silent: Bool, completion: ((Result<Info?, Error>) -> Void)? = nil) {
        let cfg = ConfigStore.shared.config
        guard !cfg.updateUrl.isEmpty, let url = URL(string: cfg.updateUrl) else {
            completion?(.failure(UpdateError.noSource))
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("LumiType/\(Product.versionText) (macOS)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            if let error {
                DispatchQueue.main.async { completion?(.failure(UpdateError.download(error))) }
                return
            }
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = obj["version"] as? String,
                  let link = obj["url"] as? String
            else {
                DispatchQueue.main.async { completion?(.failure(UpdateError.badManifest)) }
                return
            }
            let sha = (obj["sha256"] as? String) ?? ""
            let notes = (obj["notes"] as? String) ?? ""
            let remote = Info(version: version, url: link, sha256: sha, notes: notes)
            let current = Product.version
            let newer = LumiVersion(version).map { $0 > current } ?? false
            DispatchQueue.main.async {
                self?.info = newer ? remote : nil
                completion?(.success(newer ? remote : nil))
            }
        }.resume()
    }

    /// 下载 → 校验 SHA256 → 替换 .app → 重启。
    /// 任何一步失败都会保留原应用，绝不半途覆盖。
    func install(_ info: Info, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: info.url) else {
            completion(.failure(UpdateError.badManifest))
            return
        }
        URLSession.shared.downloadTask(with: url) { [weak self] tmp, _, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { completion(.failure(UpdateError.download(error))) }
                return
            }
            guard let tmp else {
                DispatchQueue.main.async { completion(.failure(UpdateError.badManifest)) }
                return
            }
            do {
                let data = try Data(contentsOf: tmp)
                if !info.sha256.isEmpty {
                    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    guard digest.lowercased() == info.sha256.lowercased() else {
                        throw UpdateError.shaMismatch
                    }
                }
                try self.replaceBundle(withPackageAt: tmp)
                DispatchQueue.main.async {
                    completion(.success(()))
                    self.relaunch()
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    /// 只支持 .zip（内含 LumiType.app）；.dmg 交给用户手动打开，
    /// 自动挂载 + 覆盖正在运行的包不稳定，宁可让用户点一下。
    private func replaceBundle(withPackageAt package: URL) throws {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else {
            throw UpdateError.install("not running from an .app bundle")
        }
        guard package.pathExtension.lowercased() == "zip" else {
            throw UpdateError.install("unsupported package type: \(package.pathExtension)")
        }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumiTypeUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", package.path, work.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else {
            throw UpdateError.install("unzip failed")
        }
        guard let newApp = try FileManager.default
            .contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.install("no .app inside the package")
        }

        let backup = bundle.deletingLastPathComponent()
            .appendingPathComponent(bundle.lastPathComponent + ".old")
        let fm = FileManager.default
        try? fm.removeItem(at: backup)
        try fm.moveItem(at: bundle, to: backup)
        do {
            try fm.copyItem(at: newApp, to: bundle)
            try? fm.removeItem(at: backup)
        } catch {
            // 回滚：新包没盖上就把旧的放回去
            try? fm.removeItem(at: bundle)
            try? fm.moveItem(at: backup, to: bundle)
            throw UpdateError.install(error.localizedDescription)
        }
    }

    private func relaunch() {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundle, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}
