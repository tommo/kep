import Foundation
import CryptoKit

/// Symmetric encryption for ExtraNote bodies. The Java app uses
/// PBKDF2-derived AES; we use HKDF-derived AES-GCM via CryptoKit so a
/// pure-Swift dependency-free implementation is enough. The wire format
/// is internal — Mindolph won't decrypt Kep's encrypted notes (and
/// vice versa); the encrypted flag + hint round-trip via topic
/// attributes regardless.
///
/// Wire format:
///   `MINDO-ENC:v1:<base64-salt>:<base64-nonce>:<base64-ciphertext>`
///
/// Salt is 16 random bytes per encryption; nonce is 12 random bytes per
/// AES-GCM convention. Both are stored alongside the ciphertext so
/// decrypt(_:password:) is self-contained.
public enum NoteEncryption {

    public static let prefix = "MINDO-ENC:v1:"

    /// Returns true when `text` looks like a previously-encrypted blob.
    /// The UI gates "Decrypt Note…" / "Encrypt Note…" on this so the
    /// user can't double-encrypt.
    public static func looksEncrypted(_ text: String) -> Bool {
        text.hasPrefix(prefix)
    }

    /// Encrypt `plaintext` under `password`. Random salt + nonce per call
    /// so the same input never produces the same blob twice.
    public static func encrypt(plaintext: String, password: String) -> String {
        let salt = randomBytes(count: 16)
        let key = deriveKey(password: password, salt: salt)
        let nonce = AES.GCM.Nonce()
        guard let body = plaintext.data(using: .utf8),
              let sealed = try? AES.GCM.seal(body, using: key, nonce: nonce),
              let combined = sealed.combined else {
            // CryptoKit's combined output only fails for a non-12-byte
            // nonce, which we never construct. Fall through with the
            // plaintext on the off chance someone hands us a non-UTF-8
            // string we can't even encode.
            return plaintext
        }
        // The combined blob is nonce(12) + ciphertext + tag(16).
        let nonceData = combined.prefix(12)
        let ctData    = combined.suffix(from: 12)
        return "\(prefix)\(salt.base64EncodedString()):\(Data(nonceData).base64EncodedString()):\(Data(ctData).base64EncodedString())"
    }

    /// Decrypt `ciphertext` under `password`. Returns nil for any decode /
    /// authentication failure — caller treats both "wrong password" and
    /// "corrupt input" the same.
    public static func decrypt(_ ciphertext: String, password: String) -> String? {
        guard ciphertext.hasPrefix(prefix) else { return nil }
        let body = ciphertext.dropFirst(prefix.count)
        let parts = body.split(separator: ":")
        guard parts.count == 3,
              let salt = Data(base64Encoded: String(parts[0])),
              let nonceData = Data(base64Encoded: String(parts[1])),
              let ctData = Data(base64Encoded: String(parts[2])),
              let nonce = try? AES.GCM.Nonce(data: nonceData) else { return nil }
        let key = deriveKey(password: password, salt: salt)
        // AES.GCM.SealedBox(combined:) wants nonce + ct + tag layout; we
        // stored ct+tag together as parts[2] so concat with the nonce.
        let combined = Data(nonceData) + ctData
        guard let sealed = try? AES.GCM.SealedBox(combined: combined),
              let plain = try? AES.GCM.open(sealed, using: key) else { return nil }
        _ = nonce // referenced only to validate the nonce shape above
        return String(data: plain, encoding: .utf8)
    }

    // MARK: - Key derivation

    private static func deriveKey(password: String, salt: Data) -> SymmetricKey {
        let pwd = SymmetricKey(data: Data(password.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: pwd,
            salt: salt,
            info: Data("kep-note".utf8),
            outputByteCount: 32
        )
    }

    private static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}
