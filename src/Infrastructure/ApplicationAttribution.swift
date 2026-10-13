import Foundation
import Security

struct ApplicationAttribution {
    let url: URL
    let evidence: LocalizedText
    let verified: Bool
    let sharedWith: [String]

    static func groups(_ app: URL) -> [String] {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess else { return [] }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dict = information as? [String: Any], let entitlements = dict[kSecCodeInfoEntitlementsDict as String] as? [String: Any] else { return [] }
        return (entitlements["com.apple.security.application-groups"] as? [String] ?? []).filter {
            !$0.contains("/") && !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }

    static func discover(app: URL, name: String, identifier: String?, home: URL,
                         groupOwners: [String: [String]], cachedGroups: [String]? = nil, identifierOwners: [String: [String]] = [:]) -> [ApplicationAttribution] {
        guard let identifier, identifier.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil else { return [] }
        let library = home.appendingPathComponent("Library")
        let peers = (identifierOwners[identifier.lowercased()] ?? []).filter { $0 != app.path }
        var values: [ApplicationAttribution] = []
        var seen = Set<String>()
        func add(_ url: URL, _ evidence: LocalizedText, verified: Bool, shared: [String] = []) {
            guard let s = DiskScanner.metadata(url), (s.st_mode & S_IFMT) != S_IFLNK,
                  canonicalFilePath(url) == url.path, seen.insert(url.path).inserted else { return }
            values.append(ApplicationAttribution(url: url, evidence: evidence, verified: verified, sharedWith: shared))
        }
        for relative in ["Caches/\(identifier)", "Containers/\(identifier)", "HTTPStorages/\(identifier)",
                         "WebKit/\(identifier)", "Preferences/\(identifier).plist", "Saved Application State/\(identifier).savedState",
                         "Application Support/\(identifier)"] {
            add(library.appendingPathComponent(relative), .message("Bundle ID: \(identifier)"), verified: true, shared: peers)
        }
        if !name.isEmpty && !name.contains("/") && name != "." && name != ".." {
            add(library.appendingPathComponent("Application Support/\(name)"), .message("Coincidencia de nombre; conservar y revisar"), verified: false)
        }
        let byHost = library.appendingPathComponent("Preferences/ByHost")
        for url in (try? FileManager.default.contentsOfDirectory(at: byHost, includingPropertiesForKeys: nil)) ?? [] {
            let prefix = identifier + "."
            let file = url.deletingPathExtension().lastPathComponent
            if file.hasPrefix(prefix), UUID(uuidString: String(file.dropFirst(prefix.count))) != nil {
                add(url, .message("Preferencia ByHost: \(identifier)"), verified: true, shared: peers)
            }
        }
        let agents = library.appendingPathComponent("LaunchAgents")
        for url in (try? FileManager.default.contentsOfDirectory(at: agents, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "plist" {
            guard let s = DiskScanner.metadata(url), (s.st_mode & S_IFMT) == S_IFREG, s.st_size < 262_144,
                  let data = try? Data(contentsOf: url), let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first,
                  program.hasPrefix("/"), pathIsWithin(canonicalFilePath(URL(fileURLWithPath: program)), root: canonicalFilePath(app)) else { continue }
            add(url, .message("LaunchAgent con ejecutable dentro de la app; desactivar el agente antes de borrar"), verified: true)
        }
        for group in cachedGroups ?? groups(app) {
            let others = (groupOwners[group] ?? []).filter { $0 != app.path }
            add(library.appendingPathComponent("Group Containers/\(group)"), .message("Grupo declarado en la firma: \(group)"),
                verified: true, shared: others)
        }
        return values
    }
}
