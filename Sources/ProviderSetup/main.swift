import Foundation
import SecurityKernel
import ModelRuntime
import CloudRuntime

// ProviderSetup — stores a provider API key in the Keychain. The key is read
// ONLY from the environment (AIOS_ZAI_KEY for the zai provider) or typed on
// stdin; it is never accepted as a command-line argument and never echoed.

let arguments = Array(CommandLine.arguments.dropFirst())
guard let providerID = arguments.first, !providerID.hasPrefix("-") else {
    try? FileHandle.standardError.write(contentsOf: Data("usage: ProviderSetup <providerID>\n".utf8))
    exit(2)
}

let envVar = "AIOS_\(providerID.uppercased())_KEY"
let key: String
if let fromEnv = ProcessInfo.processInfo.environment[envVar], !fromEnv.isEmpty {
    key = fromEnv
} else {
    try? FileHandle.standardError.write(contentsOf: Data("Paste the \(providerID) API key (input hidden; Ctrl-D to abort): ".utf8))
    guard let line = readLine(strippingNewline: true), !line.isEmpty else {
        try? FileHandle.standardError.write(contentsOf: Data("\nno key provided; aborting.\n".utf8))
        exit(1)
    }
    key = line
}

let broker = CredentialBroker()
do {
    try broker.setProviderKey(key, provider: providerID)
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("ProviderSetup: Keychain error: \(error)\n".utf8))
    exit(1)
}
print("Stored \(providerID) key in Keychain (service: aios.provider.\(providerID)). The key was not logged.")
exit(0)
