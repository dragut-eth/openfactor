import Foundation

/// Length prefixed padding, so a sealed payload's size says less than it otherwise would.
///
/// AES-GCM output is exactly the length of its input, so without this the number of bytes in an
/// item would leak how long somebody's issuer and account name are. `docs/BACKUP_FORMAT.md`
/// discloses that leak for the archive rather than fixing it, because padding an interchange
/// format is a format change; here it costs a few bytes an item and is worth having.
///
/// The prefix is what makes it unambiguous. Padding with zeroes alone would be undoable only by
/// guessing whether trailing zeroes were data, and a secret is bytes rather than text, so
/// trailing zeroes are perfectly legal content.
enum VaultPadding {

    /// Payloads round up to this. Small enough that an account costs little, large enough that
    /// ordinary issuer and name lengths collapse into one bucket.
    static let bucket = 128

    /// `length ‖ bytes ‖ zeroes`, rounded up to the next whole bucket.
    static func pad(_ data: Data) -> Data {
        var out = Data()
        out.reserveCapacity(4 + data.count + bucket)
        out.append(contentsOf: withUnsafeBytes(of: UInt32(data.count).bigEndian, Array.init))
        out.append(data)

        let remainder = out.count % bucket
        if remainder != 0 {
            out.append(Data(repeating: 0, count: bucket - remainder))
        }
        return out
    }

    /// - Returns: `nil` when the prefix does not describe something that fits, which means the
    ///   bytes are not a padded payload rather than that the payload is empty.
    static func unpad(_ data: Data) -> Data? {
        guard data.count >= 4 else { return nil }

        let length = data.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length <= UInt32(data.count - 4) else { return nil }

        return data.dropFirst(4).prefix(Int(length))
    }
}
