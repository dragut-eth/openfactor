import Foundation

/// Enough of the protocol buffers wire format to read one known message.
///
/// **This is not a protobuf implementation and must not grow into one.** It reads the four
/// wire types, hands back fields in the order they appear, and knows nothing about schemas,
/// descriptors, reflection, JSON mapping, or any of the rest. Everything it does not need is
/// absent rather than unimplemented.
///
/// Taking `SwiftProtobuf` instead would be a few lines of manifest and would break the rule
/// that every dependency is code a user has to trust without choosing to. The wire format is
/// [seven paragraphs of specification](https://protobuf.dev/programming-guides/encoding/);
/// the library is tens of thousands of lines, and this app would be handing camera input to
/// all of it.
///
/// ## Every input is hostile
///
/// This is fed by a camera, which is the widest surface in the app: a QR code is bytes from
/// a stranger, and a person pointing a phone at one has made no security decision. So:
///
/// - **Every read is bounds checked**, and running off the end is an error rather than a
///   crash or a silent zero.
/// - **Nothing is allocated to a length the input claims.** A length delimited field is
///   checked against what actually remains before a single byte is copied, so a varint
///   saying "four gigabytes follow" costs one comparison.
/// - **Varints are bounded at ten bytes**, which is the most a 64 bit value can occupy. A
///   run of continuation bits cannot spin this forever.
/// - **Groups are refused.** They are deprecated, unused here, and the only wire type whose
///   skip logic is recursive, which is the shape stack exhaustion comes in.
enum ProtobufReader {

    enum ReadError: Error, Equatable {
        case truncated
        case malformedVarint
        case unsupportedWireType(Int)
    }

    /// One field, as it appeared on the wire.
    enum Field: Equatable {
        case varint(number: Int, value: UInt64)
        case lengthDelimited(number: Int, bytes: Data)
        case fixed64(number: Int, value: UInt64)
        case fixed32(number: Int, value: UInt32)

        var number: Int {
            switch self {
            case let .varint(number, _),
                let .lengthDelimited(number, _),
                let .fixed64(number, _),
                let .fixed32(number, _):
                number
            }
        }
    }

    /// Reads every field of one message, in wire order.
    ///
    /// Unknown field numbers are returned like any other and left for the caller to ignore,
    /// which is what the wire format expects of a reader meeting a newer writer.
    static func fields(in data: Data) throws(ReadError) -> [Field] {
        var fields: [Field] = []
        var offset = data.startIndex

        while offset < data.endIndex {
            let key = try varint(in: data, at: &offset)
            let number = Int(key >> 3)
            let wireType = Int(key & 0b111)

            // Field numbers start at one. A zero means the bytes are not what they claim,
            // and continuing would produce a plausible looking message out of noise.
            guard number > 0 else { throw .malformedVarint }

            switch wireType {
            case 0:
                fields.append(.varint(number: number, value: try varint(in: data, at: &offset)))

            case 1:
                fields.append(
                    .fixed64(number: number, value: try fixed(in: data, at: &offset, bytes: 8))
                )

            case 2:
                let length = try varint(in: data, at: &offset)
                // Checked against what remains before anything is copied. The length is the
                // attacker's number, and `Data(count:)` would believe it.
                guard length <= UInt64(data.endIndex - offset) else { throw .truncated }
                let end = offset + Int(length)
                fields.append(.lengthDelimited(number: number, bytes: data[offset..<end]))
                offset = end

            case 5:
                fields.append(
                    .fixed32(
                        number: number,
                        value: UInt32(try fixed(in: data, at: &offset, bytes: 4))
                    )
                )

            // 3 and 4 are the start and end of a group, deprecated since 2008 and the only
            // construct here that would need recursion to skip. Nothing this app reads uses
            // them, so they are refused rather than handled.
            default:
                throw .unsupportedWireType(wireType)
            }
        }

        return fields
    }

    /// A base 128 varint, little endian, seven bits per byte, high bit as continuation.
    private static func varint(in data: Data, at offset: inout Data.Index) throws(ReadError) -> UInt64 {
        var value: UInt64 = 0
        var shift: UInt64 = 0

        while true {
            guard offset < data.endIndex else { throw .truncated }
            let byte = data[offset]
            offset += 1

            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }

            shift += 7
            // Ten groups of seven bits is the most a 64 bit value occupies. Past that the
            // input is either lying or padded, and either way there is nothing to read.
            guard shift < 70 else { throw .malformedVarint }
        }
    }

    private static func fixed(
        in data: Data,
        at offset: inout Data.Index,
        bytes count: Int
    ) throws(ReadError) -> UInt64 {
        guard data.endIndex - offset >= count else { throw .truncated }

        var value: UInt64 = 0
        for index in 0..<count {
            value |= UInt64(data[offset + index]) << (8 * UInt64(index))
        }
        offset += count

        return value
    }
}
