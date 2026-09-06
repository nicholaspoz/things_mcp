import AppKit
import Darwin
import Foundation

// Native URL transport only. Gleam owns Things payloads, tokens, and write semantics.
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

func readDispatchURL(request: Int32) -> URL? {
    let input = openat(request, "request.url", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard input >= 0 else { return nil }
    defer { close(input) }
    var metadata = stat()
    let limit = 1_048_576
    guard fstat(input, &metadata) == 0,
          (metadata.st_mode & S_IFMT) == S_IFREG,
          metadata.st_uid == getuid(), (metadata.st_mode & 0o077) == 0,
          metadata.st_nlink == 1, metadata.st_size > 0,
          metadata.st_size <= limit else { return nil }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 16_384)
    while true {
        let count = read(input, &buffer, buffer.count)
        if count < 0 && errno == EINTR { continue }
        guard count >= 0, data.count + count <= limit else { return nil }
        if count == 0 { break }
        data.append(contentsOf: buffer.prefix(count))
    }
    guard let text = String(data: data, encoding: .utf8),
          let parts = URLComponents(string: text), parts.scheme == "things",
          parts.host == nil || parts.host == "",
          parts.user == nil, parts.password == nil, parts.port == nil,
          parts.fragment == nil, parts.path == "/json" else { return nil }
    return parts.url
}

func loadDispatchURL(path: String) -> URL? {
    let file = URL(fileURLWithPath: path)
    let nonce = file.deletingLastPathComponent().lastPathComponent
    let expected = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/things-mcp/callbacks")
        .appendingPathComponent(nonce).appendingPathComponent("request.url").path
    guard path == expected, nonce.utf8.count == 32,
          nonce.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
    let root = callbackRoot()
    guard root >= 0 else { return nil }
    defer { close(root) }
    let request = openPrivateDirectory(root, nonce)
    guard request >= 0 else { return nil }
    defer { close(request) }
    return readDispatchURL(request: request)
}

func dispatchInBackground(path: String) -> Bool {
    guard let url = loadDispatchURL(path: path),
          let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.culturedcode.ThingsMac") else { return false }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.addsToRecentItems = false
    configuration.promptsUserIfNeeded = false
    var finished = false
    var succeeded = false
    NSWorkspace.shared.open([url], withApplicationAt: applicationURL, configuration: configuration) { application, error in
        DispatchQueue.main.async {
            succeeded = application != nil && error == nil
            finished = true
        }
    }
    // Pump the main run loop so completion cannot deadlock on the main queue.
    // This only acknowledges URL delivery; Gleam still waits for Things' callback.
    let deadline = ProcessInfo.processInfo.systemUptime + 8
    while !finished && ProcessInfo.processInfo.systemUptime < deadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    }
    return finished && succeeded
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Reapply after AppKit has processed the bundle's launch configuration.
        NSApplication.shared.setActivationPolicy(.prohibited)
    }

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
    if URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent == "ThingsURLDispatch" {
        require(Bundle.main.bundleIdentifier != "local.things-mcp.callback", "dispatcher has no relay bundle identity")
    }
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
    let request = openPrivateDirectory(root, nonce)
    require(request >= 0, "dispatch test request directory")
    defer { close(request) }
    let urlFile = requestURL.appendingPathComponent("request.url")
    let sampleURL = "things:///json?data=%5B%5D&auth-token=private-test-value"
    FileManager.default.createFile(atPath: urlFile.path, contents: Data(sampleURL.utf8), attributes: [.posixPermissions: 0o600])
    require(readDispatchURL(request: request)?.absoluteString == sampleURL, "private URL read preserves encoding")
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: urlFile.path)
    require(readDispatchURL(request: request) == nil, "publicly readable URL rejected")
    try FileManager.default.removeItem(at: urlFile)
    try FileManager.default.createSymbolicLink(at: urlFile, withDestinationURL: rootURL)
    require(readDispatchURL(request: request) == nil, "symlink URL rejected")
    try FileManager.default.removeItem(at: urlFile)
    FileManager.default.createFile(atPath: urlFile.path, contents: Data("https://example.com/".utf8), attributes: [.posixPermissions: 0o600])
    require(readDispatchURL(request: request) == nil, "unrelated URL scheme rejected")
    try FileManager.default.removeItem(at: urlFile)
    FileManager.default.createFile(atPath: urlFile.path, contents: Data(repeating: 65, count: 1_048_577), attributes: [.posixPermissions: 0o600])
    require(readDispatchURL(request: request) == nil, "oversized URL file rejected")
    try FileManager.default.removeItem(at: urlFile)
    require(loadDispatchURL(path: urlFile.path) == nil, "dispatch path outside callback root rejected")
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

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    do { try selfTest() } catch {
        FileHandle.standardError.write(Data("FAIL: callback self-test I/O error\n".utf8))
        exit(1)
    }
} else if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--dispatch" {
    // Only the unbundled executable dispatches; it must not compete with the
    // persistent relay's registered URL identity or acquire keyboard focus.
    if Bundle.main.bundleIdentifier == "local.things-mcp.callback" {
        FileHandle.standardError.write(Data("Use the unbundled Things URL dispatcher\n".utf8))
        exit(1)
    }
    NSApplication.shared.setActivationPolicy(.prohibited)
    if !dispatchInBackground(path: CommandLine.arguments[2]) {
        FileHandle.standardError.write(Data("Things URL delivery failed or timed out\n".utf8))
        exit(1)
    }
} else if CommandLine.arguments.count == 1 {
    let application = NSApplication.shared
    let delegate = ApplicationDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.prohibited)
    withExtendedLifetime(delegate) { application.run() }
} else {
    FileHandle.standardError.write(Data("Invalid callback helper arguments\n".utf8))
    exit(1)
}
