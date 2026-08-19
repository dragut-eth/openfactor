import Foundation
import Testing

@testable import OpenFactorCore

/// The sniff that chooses which reader sees a file, and the two ways it was defeated.
@Suite("JSON sniff")
struct JSONSniffTests {

    private let json = Data("{\"format\":1}".utf8)

    @Test("Ordinary JSON is recognised and handed on unchanged")
    func ordinaryJSON() {
        #expect(JSONSniff.body(of: json) == json)
    }

    /// **A byte order mark used to hide an archive.** Its holder was told no accounts were found
    /// and never asked for a passphrase, while the reader one layer down strips that exact mark
    /// on purpose.
    @Test("A byte order mark is dropped rather than hiding the file")
    func byteOrderMark() {
        let marked = Data([0xEF, 0xBB, 0xBF]) + json

        #expect(!JSONSniff.body(of: marked).isEmpty, "recognised")
        #expect(JSONSniff.body(of: marked) == json, "and the mark is gone, so the parser can read it")
    }

    @Test("Leading whitespace is not an obstacle either")
    func leadingWhitespace() {
        #expect(!JSONSniff.body(of: Data("  \n\t".utf8) + json).isEmpty)
    }

    /// **The RTF guard used to run before the whitespace skip**, so a newline walked past it.
    @Test("RTF is refused, with or without whitespace in front of it")
    func rtfIsRefused() {
        let rtf = Data("{\\rtf1 whatever".utf8)

        #expect(JSONSniff.body(of: rtf).isEmpty)
        #expect(JSONSniff.body(of: Data("\n\n  ".utf8) + rtf).isEmpty)
        #expect(JSONSniff.body(of: Data([0xEF, 0xBB, 0xBF]) + rtf).isEmpty, "nor behind a mark")
    }

    @Test("Anything that is not an object is not JSON to this app")
    func notAnObject() {
        #expect(JSONSniff.body(of: Data("[1,2,3]".utf8)).isEmpty)
        #expect(JSONSniff.body(of: Data("Account Name: x".utf8)).isEmpty)
        #expect(JSONSniff.body(of: Data()).isEmpty)
    }
}
