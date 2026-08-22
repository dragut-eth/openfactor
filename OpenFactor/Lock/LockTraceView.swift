#if DEBUG

    import SwiftUI

    /// Reads the lock trace back on the device that produced it.
    ///
    /// **Newest first**, because the thing worth reading is always the last few events, and the
    /// buffer holds hundreds. Monospaced, because the lines are columns and columns that do not
    /// line up cannot be scanned.
    ///
    /// **Copy is the point of the screen.** The sequence has to leave the phone to be useful, and
    /// retyping forty lines of state from a photograph of a screen is how a transcription error
    /// becomes an hour of chasing a bug that was never there.
    struct LockTraceView: View {

        @State private var trace = LockTrace.shared
        @State private var copied = false

        var body: some View {
            List {
                Section {
                    Button {
                        UIPasteboard.general.string = trace.text
                        withAnimation(.snappy) { copied = true }
                    } label: {
                        Label(
                            copied ? "Copied" : "Copy the whole trace",
                            systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(trace.lines.isEmpty)

                    Button("Clear", role: .destructive) {
                        trace.clear()
                        copied = false
                    }
                    .disabled(trace.lines.isEmpty)
                } footer: {
                    Text(
                        """
                        Clear, then run one sequence, then read. A trace that spans three \
                        experiments is harder to read than three traces.

                        phase and settling are the two values that decide the cover. \
                        cover=0 with locked=0 means the switcher is about to photograph the \
                        account list.
                        """
                    )
                }

                Section {
                    if trace.lines.isEmpty {
                        Text("Nothing recorded yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(trace.lines.enumerated().reversed()), id: \.offset) { entry in
                            Text(entry.element)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    Text("\(trace.lines.count) events, newest first")
                }
            }
            .navigationTitle("Lock trace")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

#endif
