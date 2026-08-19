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

    // MARK: - Gate A4, scope 4

    /// **The rule was pinned by no test**, which a review filed on its own. It is one boolean and
    /// it decides whether somebody's recovery credential may leave the device, so the tidy-looking
    /// change of making the two call sites consistent would be a serious defect.
    @Test("A passphrase never leaves the device and a code may")
    func theTwoRulesAreDifferentOnPurpose() {
        #expect(CodeClipboard.rules(for: .passphrase).localOnly)
        #expect(!CodeClipboard.rules(for: .code).localOnly)
    }

    /// The expiry does not travel between devices, as measured, so it protects only the copy on
    /// the device that made it. That is why the rule above carries the weight and this does not.
    @Test("A passphrase is given a shorter life than it would need to be safe on its own")
    func lifetimesAreStated() {
        #expect(CodeClipboard.rules(for: .code).lifetime == 30)
        #expect(CodeClipboard.rules(for: .passphrase).lifetime == 120)
    }
}
