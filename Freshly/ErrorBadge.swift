import AppKit
import SwiftUI
import FreshlyModels

/// The warning triangle on a row whose check or install failed. A tooltip
/// alone is easy to miss and invisible to VoiceOver users browsing the list,
/// so the badge is a button that pops the full message over the row.
struct ErrorBadge: View {
    let error: UpdateError

    @State private var showingDetails = false

    var body: some View {
        Button {
            showingDetails.toggle()
        } label: {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.yellow)
        }
        .buttonStyle(.borderless)
        .help(error.message)
        .accessibilityLabel(Text("Update failed: \(error.message)"))
        .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(error.message)
                    .textSelection(.enabled)
                    .frame(maxWidth: 320, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if error.code == .permissionDenied {
                    Button("Open System Settings") {
                        showingDetails = false
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}
