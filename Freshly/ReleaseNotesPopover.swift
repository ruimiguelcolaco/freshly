import AppKit
import SwiftUI
import FreshlyModels
import FreshlySources

/// The "what's new" affordance on an outdated row: pops the release notes
/// over the row so the user can see what an update brings before applying
/// it, with the update action right there in the popover.
struct ReleaseNotesButton: View {
    let status: AppUpdateStatus
    let release: ReleaseInfo

    @State private var showingNotes = false

    var body: some View {
        Button {
            showingNotes.toggle()
        } label: {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(String(localized: "What's new in \(status.app.name) \(release.version.rawValue)"))
        .accessibilityLabel(Text("What's new in \(status.app.name) \(release.version.rawValue)"))
        .popover(isPresented: $showingNotes, arrowEdge: .bottom) {
            ReleaseNotesView(status: status, release: release, isPresented: $showingNotes)
        }
    }
}

private struct ReleaseNotesView: View {
    @Environment(AppListStore.self) private var store

    let status: AppUpdateStatus
    let release: ReleaseInfo
    @Binding var isPresented: Bool

    private enum NotesState {
        case loading
        case loaded(AttributedString)
        case unavailable
        case failed(String)
    }

    @State private var state: NotesState = .loading

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(12)
            Divider()
            notesBody
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            footer
                .padding(12)
        }
        .frame(width: 460)
        .task { await loadNotes() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(status.app.name) \(release.version.rawValue)")
                .font(.headline)
            HStack(spacing: 4) {
                Text(release.source.displayName)
                if let published = release.publishedAt {
                    Text(verbatim: "·")
                    Text(published, format: .dateTime.day().month().year())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var notesBody: some View {
        switch state {
        case .loading:
            ProgressView("Loading release notes…")
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 80)
        case .loaded(let notes):
            ScrollView {
                Text(notes)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 60, maxHeight: 300)
        case .unavailable:
            Text("No release notes were provided for this version.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        case .failed(let message):
            Text(message)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack {
            if let page = release.releaseNotesURL {
                Button("Open in Browser…") {
                    NSWorkspace.shared.open(page)
                }
            }
            Spacer()
            Button("Update") {
                isPresented = false
                store.requestUpdate(for: status)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.installing[status.id] != nil)
        }
    }

    private func loadNotes() async {
        do {
            guard let notes = try await ReleaseNotesLoader().load(for: release) else {
                state = .unavailable
                return
            }
            state = if let rendered = Self.render(notes) {
                .loaded(rendered)
            } else {
                .unavailable
            }
        } catch let error as UpdateError {
            state = .failed(error.message)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Rendering

    static func render(_ notes: ReleaseNotes) -> AttributedString? {
        switch notes {
        case .html(let html):
            renderHTML(html)
        case .markdown(let markdown):
            renderMarkdown(markdown)
        case .plainText(let text):
            AttributedString(text)
        }
    }

    /// WebKit's importer bakes in fonts and colors; the CSS pins the font
    /// to the system one and clearing the colors afterwards lets the text
    /// adapt to light/dark. Embedded media is stripped — the importer
    /// would fetch it synchronously.
    private static func renderHTML(_ html: String) -> AttributedString? {
        let sanitized = html.replacingOccurrences(
            of: "</?(img|picture|script|iframe|video|audio|source|object|embed)[^>]*>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let styled = "<style>body { font-family: -apple-system, sans-serif; font-size: 13px; }</style>" + sanitized
        guard let data = styled.data(using: .utf8),
              let imported = try? NSAttributedString(
                  data: data,
                  options: [
                      .documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue,
                  ],
                  documentAttributes: nil
              ) else {
            return nil
        }
        var rendered = AttributedString(imported)
        rendered.foregroundColor = nil
        return rendered
    }

    /// Foundation's Markdown parsing is inline-only, so block syntax GitHub
    /// bodies lean on is folded into it: headings become bold lines and
    /// list markers become bullets.
    private static func renderMarkdown(_ markdown: String) -> AttributedString {
        let lines = markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") {
                    let title = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                    return "**\(title)**"
                }
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    return "• " + trimmed.dropFirst(2)
                }
                return String(raw)
            }
        let folded = lines.joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: folded, options: options))
            ?? AttributedString(markdown)
    }
}
