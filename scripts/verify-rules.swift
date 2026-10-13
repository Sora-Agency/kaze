import Foundation
import CryptoKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let rules = root.appendingPathComponent("src/Rules")
let infoData = try Data(contentsOf: root.appendingPathComponent("src/Info.plist"))
let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as! [String: Any]
let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: info["SUPublicEDKey"] as! String)!)
let bytes = try Data(contentsOf: rules.appendingPathComponent("rules-v1.json"))
let signature = try String(contentsOf: rules.appendingPathComponent("rules-v1.signature"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
guard let data = Data(base64Encoded: signature), key.isValidSignature(data, for: bytes) else {
    fputs("Invalid cleanup rule signature.\n", stderr); exit(1)
}
let manifest = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
guard manifest["schema"] as? Int == 1, manifest["version"] as? Int == 2 else { exit(1) }
print("Cleanup rule signature verified.")
