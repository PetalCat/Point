import Flutter
import Foundation
import Security

/// Native iOS Keychain bridge (P0-01 / P1-13).
///
/// flutter_secure_storage_darwin crashes on iOS 26, so Point uses this thin
/// MethodChannel for at-rest secure storage of auth tokens, MLS state, the
/// location cache, and learned zones. Items are stored with
/// kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly so they survive locks but
/// never sync to iCloud or leave the device.
enum KeychainChannel {
  static let channelName = "dev.petalcat.point/keychain"
  private static let service = "dev.petalcat.point"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "write":
        guard let args = call.arguments as? [String: Any],
              let key = args["key"] as? String,
              let value = args["value"] as? String else {
          result(FlutterError(code: "bad_args", message: "key/value required", details: nil))
          return
        }
        result(write(key: key, value: value))
      case "read":
        guard let args = call.arguments as? [String: Any],
              let key = args["key"] as? String else {
          result(FlutterError(code: "bad_args", message: "key required", details: nil))
          return
        }
        result(read(key: key))
      case "delete":
        guard let args = call.arguments as? [String: Any],
              let key = args["key"] as? String else {
          result(FlutterError(code: "bad_args", message: "key required", details: nil))
          return
        }
        delete(key: key)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func baseQuery(_ key: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
  }

  private static func write(key: String, value: String) -> Bool {
    let data = Data(value.utf8)
    // Replace any existing item.
    SecItemDelete(baseQuery(key) as CFDictionary)
    var attrs = baseQuery(key)
    attrs[kSecValueData as String] = data
    attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(attrs as CFDictionary, nil)
    return status == errSecSuccess
  }

  private static func read(key: String) -> String? {
    var query = baseQuery(key)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private static func delete(key: String) {
    SecItemDelete(baseQuery(key) as CFDictionary)
  }
}
