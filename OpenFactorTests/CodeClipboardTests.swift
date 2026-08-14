import Foundation
import Testing
import UIKit

@testable import OpenFactor

/// The clipboard is the widest exposure in the app: every other app the user opens can
/// read it. These tests pin the two options that narrow it.
///
/// They run in the app process, which is the only place `UIPasteboard` behaves like it
/// does on a device.
@MainActor
@Suite("Clipboard", .serialized)
struct CodeClipboardTests {

    @Test("Copying puts the code on the pasteboard")
    func copiesTheCode() {
        UIPasteboard.general.items = []

        CodeClipboard.copy("751702", expiring: Date().addingTimeInterval(25))

        #expect(UIPasteboard.general.string == "751702")
    }

    /// Proves the expiry is real rather than merely passed. An entry whose expiry has
    /// already gone is not on the pasteboard at all, so if the system were ignoring the
    /// option this would come back with the code in it.
    @Test("An expired entry is not readable")
    func expiredEntryIsGone() {
        UIPasteboard.general.items = []

        CodeClipboard.copy("751702", expiring: Date().addingTimeInterval(-1))

        #expect(UIPasteboard.general.string != "751702")
    }

    @Test("Copying replaces whatever was there rather than adding to it")
    func replacesPreviousContents() {
        UIPasteboard.general.items = []

        CodeClipboard.copy("111111", expiring: Date().addingTimeInterval(25))
        CodeClipboard.copy("222222", expiring: Date().addingTimeInterval(25))

        #expect(UIPasteboard.general.string == "222222")
        #expect(UIPasteboard.general.items.count == 1)
    }
}
