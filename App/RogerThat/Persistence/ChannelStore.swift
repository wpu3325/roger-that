import Foundation
import Security
import RogerThatCore

/// Persists the joined-channels list across launches.
///
/// Split storage by sensitivity: channel **metadata** (id, name, kind, joinedAt) goes in
/// UserDefaults as JSON; the secret **key** goes in the Keychain, keyed by channelID. So a
/// UserDefaults dump never leaks keys, and removing a channel scrubs its key.
final class ChannelStore {

    private let metaKey = "rogerthat.joinedChannels.v1"
    private let keychainService = "com.wilsonpu.rogerthat.channelkey"

    /// Load every joined channel that still has its key in the Keychain, in saved order.
    func load() -> [(meta: ChannelMetadata, channel: Channel)] {
        loadMetas().compactMap { meta in
            guard let keyData = keychainLoad(account: meta.channelID),
                  let key = ChannelCrypto.key(from: keyData) else { return nil }
            return (meta, Channel(channelID: meta.channelID, key: key))
        }
    }

    /// Add (or update) a channel: key to Keychain, metadata appended if new.
    func add(_ meta: ChannelMetadata, channel: Channel) {
        keychainSave(account: meta.channelID, data: ChannelCrypto.keyData(channel.key))
        var metas = loadMetas()
        if let i = metas.firstIndex(where: { $0.channelID == meta.channelID }) {
            metas[i] = meta
        } else {
            metas.append(meta)
        }
        saveMetas(metas)
    }

    /// Remove a channel and scrub its key.
    func remove(_ channelID: String) {
        keychainDelete(account: channelID)
        saveMetas(loadMetas().filter { $0.channelID != channelID })
    }

    // MARK: - Metadata (UserDefaults)

    private func loadMetas() -> [ChannelMetadata] {
        guard let data = UserDefaults.standard.data(forKey: metaKey),
              let metas = try? JSONDecoder().decode([ChannelMetadata].self, from: data) else { return [] }
        return metas
    }

    private func saveMetas(_ metas: [ChannelMetadata]) {
        guard let data = try? JSONEncoder().encode(metas) else { return }
        UserDefaults.standard.set(data, forKey: metaKey)
    }

    // MARK: - Keys (Keychain)

    private func keychainQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: account]
    }

    private func keychainSave(account: String, data: Data) {
        SecItemDelete(keychainQuery(account: account) as CFDictionary)   // replace any existing
        var add = keychainQuery(account: account)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private func keychainLoad(account: String) -> Data? {
        var query = keychainQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    private func keychainDelete(account: String) {
        SecItemDelete(keychainQuery(account: account) as CFDictionary)
    }
}
