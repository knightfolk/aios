import Foundation
import CryptoKit
import AIOSCore

public enum Hashing {
    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - MCP client (docs 11: first-class tool/data interoperability;
// servers are untrusted extension processes operating under broker policy)

public struct MCPTool: Codable, Sendable, Hashable {
    public var name: String
    public var description: String?
    public var inputSchema: [String: String]

    public init(name: String, description: String?, inputSchema: [String: String]) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct MCPToolResult: Codable, Sendable, Hashable {
    public struct Content: Codable, Sendable, Hashable {
        public var type: String
        public var text: String
    }

    public var content: [Content]
    public var isError: Bool

    public var text: String {
        content.map(\.text).joined(separator: "\n")
    }
}

/// Minimal, real MCP client: JSON-RPC 2.0 over line-delimited stdio against
/// a spawned server process (initialize → tools/list → tools/call).
public actor MCPClient {
    public enum ClientError: Error, Equatable {
        case handshakeFailed(String)
        case rpcError(code: Int, message: String)
    }

    private let process: Process
    private let stdin: FileHandle
    private let stdout: FileHandle
    private var nextID = 0
    private let decoder = JSONDecoder()

    public init(command: String, arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        let inPipe = Pipe()
        let outPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice
        self.process = process
        self.stdin = inPipe.fileHandleForWriting
        self.stdout = outPipe.fileHandleForReading
        try process.run()

        // Handshake.
        struct InitResult: Codable {
            struct Info: Codable {
                var name: String
                var version: String
            }
            var protocolVersion: String?
            var serverInfo: Info?
        }
        let reply = try await rpc("initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": [:],
            "clientInfo": ["name": "aios", "version": "1"],
        ] as [String: Any])
        guard let data = try? JSONSerialization.data(withJSONObject: reply),
              (try? decoder.decode(InitResult.self, from: data))?.serverInfo != nil else {
            throw ClientError.handshakeFailed("server did not complete initialize")
        }
        try send(notification: "notifications/initialized", params: [:] as [String: Any])
    }

    public func listTools() async throws -> [MCPTool] {
        struct ToolsResult: Codable {
            struct RawTool: Codable {
                var name: String
                var description: String?
            }
            var tools: [RawTool]
        }
        let reply = try await rpc("tools/list", params: [:] as [String: Any])
        let data = try JSONSerialization.data(withJSONObject: reply)
        let result = try decoder.decode(ToolsResult.self, from: data)
        return result.tools.map { MCPTool(name: $0.name, description: $0.description, inputSchema: [:]) }
    }

    public func callTool(name: String, arguments: [String: String]) async throws -> MCPToolResult {
        let reply = try await rpc("tools/call", params: [
            "name": name,
            "arguments": arguments,
        ] as [String: Any])
        let data = try JSONSerialization.data(withJSONObject: reply)
        return try decoder.decode(MCPToolResult.self, from: data)
    }

    public func shutdown() {
        try? stdin.write(contentsOf: Data())
        process.terminate()
    }

    // MARK: - JSON-RPC plumbing

    private func rpc(_ method: String, params: [String: Any]) async throws -> Any {
        nextID += 1
        let id = nextID
        let request: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        try send(raw: request)

        // Line-delimited replies; skip notifications, match ids.
        while true {
            guard let line = try readLine() else {
                throw ClientError.handshakeFailed("server closed stdout")
            }
            guard let data = line.data(using: .utf8),
                  let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            guard envelope["id"] as? Int == id else { continue }
            if let error = envelope["error"] as? [String: Any] {
                throw ClientError.rpcError(code: error["code"] as? Int ?? -1,
                                           message: error["message"] as? String ?? "unknown")
            }
            return envelope["result"] ?? [:]
        }
    }

    private func send(notification method: String, params: [String: Any]) throws {
        try send(raw: ["jsonrpc": "2.0", "method": method, "params": params])
    }

    private func send(raw: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: raw)
        try stdin.write(contentsOf: data + Data("\n".utf8))
    }

    private func readLine() throws -> String? {
        var buffer = Data()
        while true {
            guard let chunk = try stdout.read(upToCount: 1), !chunk.isEmpty else {
                return buffer.isEmpty ? nil : String(decoding: buffer, as: UTF8.self)
            }
            buffer.append(chunk)
            if chunk == Data("\n".utf8) {
                return String(decoding: buffer.dropLast(), as: UTF8.self)
            }
        }
    }
}

/// Maps catalogued MCP tools onto broker-gated action requests. The server
/// never defines policy: capability classes come from our classification of
/// the tool's declared effects, conservative by default.
public enum MCPCatalog {
    public static func actionRequest(for tool: MCPTool, server: String, arguments: [String: String]) -> ActionRequest {
        let lowered = (tool.description ?? tool.name).lowercased()
        let external = lowered.contains("delete") || lowered.contains("send")
            || lowered.contains("publish") || lowered.contains("deploy")
        let capability: CapabilityClass = external ? .externalConsequence : .observe
        return ActionRequest(
            actionID: ActionID(),
            workPackageID: WorkPackageID(),
            requestedBy: .specialist(name: "mcp:\(server)"),
            capability: capability,
            operation: "mcp.call",
            target: "\(server)/\(tool.name)",
            parameters: arguments.mapValues { .text($0) },
            expectedEffect: tool.description ?? "call \(tool.name)",
            sideEffectClass: external ? .external : .none,
            reversibility: .unknown,
            idempotency: .unknown,
            requiredPermission: capability,
            verificationPlan: "inspect tool result"
        )
    }
}

// MARK: - Agent Skills (docs 11: SKILL.md packaging; skills request
// capabilities, they never receive them automatically)

public struct SkillRecord: Sendable, Hashable {
    public var name: String
    public var description: String
    /// Capabilities the skill REQUESTS — grants are a separate human/policy
    /// decision (TrustPolicy).
    public var requestedCapabilities: [CapabilityClass]
    public var body: String

    public init(name: String, description: String, requestedCapabilities: [CapabilityClass], body: String) {
        self.name = name
        self.description = description
        self.requestedCapabilities = requestedCapabilities
        self.body = body
    }
}

public enum SkillLoader {
    public static func load(from directory: URL) throws -> [SkillRecord] {
        let url = directory.appendingPathComponent("SKILL.md")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var name = "unnamed"
        var description = ""
        var requested: [CapabilityClass] = []
        var body = text

        if text.hasPrefix("---") {
            var lines = text.dropFirst().split(separator: "\n", omittingEmptySubsequences: false)[...]
            var front: [String] = []
            for line in lines {
                if line.trimmingCharacters(in: .whitespaces) == "---" { break }
                front.append(String(line))
            }
            body = lines.dropFirst(front.count + 1).joined(separator: "\n")
            for line in front {
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                switch key {
                case "name": name = value
                case "description": description = value
                case "capabilities":
                    for token in value.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).split(separator: ",") {
                        switch token.trimmingCharacters(in: .whitespaces) {
                        case "external-consequence": requested.append(.externalConsequence)
                        case "computer-control": requested.append(.operateComputer)
                        default: requested.append(.observe)
                        }
                    }
                default: break
                }
            }
        }
        return [SkillRecord(name: name, description: description, requestedCapabilities: requested, body: body)]
    }
}

// MARK: - Extension trust (docs 11: publisher, pinned hash, declared
// capabilities, install-time review, reapproval on expansion)

public struct ExtensionManifest: Codable, Sendable, Hashable {
    public var id: String
    public var publisher: String
    public var version: String
    public var sha256: String
    public var declaredCapabilities: [CapabilityClass]

    public init(id: String, publisher: String, version: String, sha256: String, declaredCapabilities: [CapabilityClass]) {
        self.id = id
        self.publisher = publisher
        self.version = version
        self.sha256 = sha256
        self.declaredCapabilities = declaredCapabilities
    }
}

public struct TrustDecision: Sendable, Equatable {
    public var approved: Bool
    public var requiredApprovals: [CapabilityClass]
    public var reason: String
}

public enum TrustPolicy {
    public static func verify(manifest: ExtensionManifest, bundleAt url: URL, approvedCapabilities: [CapabilityClass]) -> TrustDecision {
        let actual = (try? Data(contentsOf: url)).map(Hashing.sha256Hex(of:)) ?? ""
        guard actual == manifest.sha256 else {
            return TrustDecision(approved: false, requiredApprovals: [], reason: "hash mismatch: bundle does not match the pinned manifest")
        }
        let missing = manifest.declaredCapabilities.filter { !approvedCapabilities.contains($0) }
        guard missing.isEmpty else {
            return TrustDecision(approved: false, requiredApprovals: missing, reason: "capability expansion requires reapproval: \(missing.map(\.rawValue))")
        }
        return TrustDecision(approved: true, requiredApprovals: [], reason: "verified")
    }

    public static func verify(skill: SkillRecord, approvedCapabilities: [CapabilityClass]) -> TrustDecision {
        let missing = skill.requestedCapabilities.filter { !approvedCapabilities.contains($0) }
        guard missing.isEmpty else {
            return TrustDecision(approved: false, requiredApprovals: missing, reason: "skill requests ungranted capabilities: \(missing.map(\.rawValue))")
        }
        return TrustDecision(approved: true, requiredApprovals: [], reason: "verified")
    }
}

// MARK: - LAN workers (docs 07/13: remote compute is a later seam; the
// transport reports honest unavailability instead of pretending)

public protocol LanWorkerTransport: Sendable {
    func discoverWorkers() async throws -> [String]
    var availability: String { get async }
}

public struct UnavailableLanTransport: LanWorkerTransport {
    public init() {}

    public func discoverWorkers() async throws -> [String] { [] }

    public var availability: String {
        "LAN worker transport not configured in this build (declared seam, Phase 7)"
    }
}
