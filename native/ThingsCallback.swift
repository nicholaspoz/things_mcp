import AppKit
import Darwin
import Foundation

// URL-event relay only. Gleam owns Things payloads, tokens, and write semantics.
struct Callback {
    let nonce: String
    let status: String
    let parameters: [String: String]

    static func parse(_ url: URL) -> Callback? {
        guard url.absoluteString.utf8.count <= 65_536,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "things-mcp-callback",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.fragment == nil,
              let nonce = parts.host,
              nonce.utf8.count == 32,
              nonce.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              ["/success", "/error", "/cancel"].contains(parts.path) else { return nil }
        var parameters: [String: String] = [:]
        for item in parts.queryItems ?? [] {
            guard !item.name.isEmpty, parameters[item.name] == nil else { return nil }
            parameters[item.name] = item.value ?? ""
        }
        return Callback(nonce: nonce, status: String(parts.path.dropFirst()), parameters: parameters)
    }

    func encoded() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["status": status, "parameters": parameters],
                                   options: [.sortedKeys])
    }
}

func privateDirectory(_ fd: Int32) -> Bool {
    var metadata = stat()
    return fd >= 0 && fstat(fd, &metadata) == 0
        && (metadata.st_mode & S_IFMT) == S_IFDIR
        && metadata.st_uid == getuid() && (metadata.st_mode & 0o077) == 0
}

func openPrivateDirectory(_ parent: Int32, _ name: String) -> Int32 {
    let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard privateDirectory(fd) else {
        if fd >= 0 { close(fd) }
        return -1
    }
    return fd
}

// Open each request-owned path component without following symbolic links.
func callbackRoot() -> Int32 {
    let caches = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches").path
    let base = open(caches, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard base >= 0 else { return -1 }
    defer { close(base) }
    let application = openPrivateDirectory(base, "things-mcp")
    guard application >= 0 else { return -1 }
    defer { close(application) }
    return openPrivateDirectory(application, "callbacks")
}

@discardableResult
func persist(_ callback: Callback, root: Int32) -> Bool {
    let request = openPrivateDirectory(root, callback.nonce)
    guard request >= 0 else { return false }
    defer { close(request) }
    let pending = openat(request, "pending", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard pending >= 0 else { return false }
    defer { close(pending) }
    var metadata = stat()
    guard fstat(pending, &metadata) == 0,
          (metadata.st_mode & S_IFMT) == S_IFREG,
          metadata.st_uid == getuid(), (metadata.st_mode & 0o077) == 0,
          difftime(time(nil), metadata.st_mtimespec.tv_sec) >= 0,
          difftime(time(nil), metadata.st_mtimespec.tv_sec) <= 300,
          let data = try? callback.encoded() else { return false }

    let temporary = ".result-" + UUID().uuidString
    let output = openat(request, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard output >= 0 else { return false }
    defer {
        close(output)
        unlinkat(request, temporary, 0)
    }
    let written = data.withUnsafeBytes { bytes -> Bool in
        var offset = 0
        while offset < bytes.count {
            let count = write(output, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { return false }
            offset += count
        }
        return true
    }
    // Linking publishes a complete file atomically and never replaces an earlier callback.
    return written && fsync(output) == 0
        && linkat(request, temporary, request, "result.json", 0) == 0
}

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        let root = callbackRoot()
        guard root >= 0 else { return }
        defer { close(root) }
        for url in urls {
            if let callback = Callback.parse(url) { persist(callback, root: root) }
        }
    }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data(("FAIL: " + message + "\n").utf8))
        exit(1)
    }
}

func selfTest() throws {
    let nonce = "0123456789abcdef0123456789abcdef"
    let prefix = "things-mcp-callback://" + nonce
    let valid = Callback.parse(URL(string: prefix + "/success?x-things-ids=abc%2Cdef&note=a%2Bb%20c")!)!
    require(valid.parameters["note"] == "a+b c", "query decoding")
    for invalid in [
        prefix + "/success?x=1&x=2", prefix + "/unexpected", prefix + "/success#fragment",
        "things-mcp-callback://../success", prefix + "/../success", prefix + "/success?=value",
        "https://" + nonce + "/success", "things-mcp-callback://user@" + nonce + "/success",
        "things-mcp-callback://" + nonce + ":12/success",
    ] {
        require(Callback.parse(URL(string: invalid)!) == nil, "reject invalid callback")
    }
    let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent("things-callback-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: rootURL) }
    let root = open(rootURL.path, O_RDONLY | O_DIRECTORY)
    defer { close(root) }
    require(privateDirectory(root), "test root private")
    require(!persist(valid, root: root), "unknown request ignored")
    let requestURL = rootURL.appendingPathComponent(nonce)
    try FileManager.default.createDirectory(at: requestURL, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
    require(!persist(valid, root: root), "missing pending ignored")
    let markerURL = requestURL.appendingPathComponent("pending")
    FileManager.default.createFile(atPath: markerURL.path, contents: Data(), attributes: [.posixPermissions: 0o600])
    require(persist(valid, root: root), "registered request accepted")
    require(!persist(valid, root: root), "duplicate callback ignored")
    let result = try Data(contentsOf: requestURL.appendingPathComponent("result.json"))
    let expected = try valid.encoded()
    require(result == expected, "result contract")
    try FileManager.default.removeItem(at: requestURL.appendingPathComponent("result.json"))
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -301)], ofItemAtPath: markerURL.path)
    require(!persist(valid, root: root), "expired marker ignored")
    try FileManager.default.removeItem(at: markerURL)
    try FileManager.default.createSymbolicLink(at: markerURL, withDestinationURL: rootURL)
    require(!persist(valid, root: root), "symlink marker ignored")
    try FileManager.default.removeItem(at: requestURL)
    try FileManager.default.createSymbolicLink(at: requestURL, withDestinationURL: rootURL)
    require(!persist(valid, root: root), "symlink request ignored")
    print("Callback relay self-tests passed")
}

if CommandLine.arguments.contains("--self-test") {
    do { try selfTest() } catch {
        FileHandle.standardError.write(Data("FAIL: callback self-test I/O error\n".utf8))
        exit(1)
    }
} else {
    let application = NSApplication.shared
    let delegate = ApplicationDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.prohibited)
    withExtendedLifetime(delegate) { application.run() }
}
