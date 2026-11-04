import Foundation

/// 持久化 LRU 缓存，对应原版 `LruCache` + `config/transcache.json`。
///
/// 行为对齐点：
/// - 命中即刷新到队尾（最近使用）；
/// - 超过上限淘汰队首（最久未使用）；
/// - 每次写入落盘，进程重启后仍可命中（原版「重复句离线秒回」）；
/// - 读取时忽略旧格式的片段条目。
public final class LruCache {

    public struct Entry: Codable, Sendable {
        public let key: String
        public let value: String
        public let stamp: Double
    }

    private var map: [String: Entry] = [:]
    private var order: [String] = []
    private let lock = NSLock()

    public private(set) var capacity: Int
    public private(set) var path: URL?

    public init(capacity: Int = 500, path: URL? = nil) {
        self.capacity = max(0, capacity)
        self.path = path
        load()
    }

    // MARK: - 读取

    public func get(_ text: String, provider: Provider, source: String, target: String) -> String? {
        let key = LruCache.key(text: text, provider: provider, source: source, target: target)
        lock.lock()
        defer { lock.unlock() }
        guard let hit = map[key] else { return nil }
        // 命中 → 移到队尾
        if let idx = order.firstIndex(of: key) {
            order.remove(at: idx)
            order.append(key)
        }
        return hit.value
    }

    // MARK: - 写入

    public func put(_ value: String, for text: String, provider: Provider, source: String, target: String) {
        guard capacity > 0 else { return }
        let key = LruCache.key(text: text, provider: provider, source: source, target: target)
        lock.lock()
        defer { lock.unlock() }
        map[key] = Entry(key: key, value: value, stamp: Date().timeIntervalSince1970)
        if let idx = order.firstIndex(of: key) { order.remove(at: idx) }
        order.append(key)
        while order.count > capacity {
            let victim = order.removeFirst()
            map.removeValue(forKey: victim)
        }
        flushLocked()
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return order.count
    }

    public var isEmpty: Bool { count == 0 }

    public func removeAll() {
        lock.lock(); defer { lock.unlock() }
        map.removeAll()
        order.removeAll()
        flushLocked()
    }

    // MARK: - 磁盘

    private struct Payload: Codable {
        let version: Int
        let entries: [Entry]
    }

    private func load() {
        guard let path, FileManager.default.fileExists(atPath: path.path) else { return }
        guard let data = try? Data(contentsOf: path) else { return }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        lock.lock()
        defer { lock.unlock() }
        // 按时间戳升序恢复使用顺序
        for e in payload.entries.sorted(by: { $0.stamp < $1.stamp }) {
            guard !e.key.isEmpty, !e.value.isEmpty else { continue }
            map[e.key] = e
            order.removeAll { $0 == e.key }
            order.append(e.key)
        }
        while order.count > capacity {
            let victim = order.removeFirst()
            map.removeValue(forKey: victim)
        }
    }

    private func flushLocked() {
        guard let path else { return }
        let entries = order.compactMap { map[$0] }
        let payload = Payload(version: 1, entries: entries)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: path, options: .atomic)
    }

    public func flush() {
        lock.lock(); defer { lock.unlock() }
        flushLocked()
    }

    // MARK: - 键

    /// 键 = FNV-1a(provider|source|target|原文)，避免把长原文直接当键
    static func key(text: String, provider: Provider, source: String, target: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(provider.rawValue)|\(source)|\(target)|\(text)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
