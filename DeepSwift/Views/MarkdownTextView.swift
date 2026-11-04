//
//  MarkdownTextView.swift
//  DeepSwift
//

import MarkdownView
import SwiftUI

/// Static Markdown presentation for durable conversation content.
///
/// `MarkdownText` is the package's continuous-text presentation: paragraphs,
/// headings, lists, and quotes are one selectable native text surface, while
/// code blocks, tables, math, and images are hosted views supplied by the same
/// parser. It is used for historical messages and settled assistant messages.
struct MarkdownTextView: View {
    let text: String

    var body: some View {
        MarkdownText(text)
            .deepSwiftMarkdownPresentation()
    }
}

/// Streaming presentation for the one assistant attempt currently in flight.
///
/// The source is owned by `MarkdownStreamCoordinator`, never by a SwiftUI body,
/// so view evaluation cannot recreate or reset the incremental parser.
struct StreamingMarkdownTextView: View {
    private let coordinator: MarkdownStreamCoordinator
    private let attemptID: String
    private let fallbackText: String

    init(coordinator: MarkdownStreamCoordinator, attemptID: String, fallbackText: String = "") {
        self.coordinator = coordinator
        self.attemptID = attemptID
        self.fallbackText = fallbackText
    }

    var body: some View {
        if let source = coordinator.source(for: attemptID) {
            StreamingMarkdownReader(source) { parseResult in
                MarkdownText(parseResult)
                    .deepSwiftMarkdownPresentation()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            MarkdownTextView(text: fallbackText)
        }
    }
}

/// Owns the streaming source for the single active assistant attempt.
///
/// At most one attempt is live at a time. Starting a new attempt finishes and
/// releases the previous source; finishing a turn or changing sessions does the
/// same. The source's text is always the accumulated text from the durable
/// projection, never a second conversation store.
@MainActor
final class MarkdownStreamCoordinator {
    private var activeAttemptID: String?
    private var activeSource: StreamingMarkdownSource?

    func synchronize(attemptID: String?, text: String) {
        guard let attemptID else {
            finish()
            return
        }

        if activeAttemptID != attemptID {
            finish()
            let source = StreamingMarkdownSource(text)
            activeAttemptID = attemptID
            activeSource = source
        } else if let source = activeSource, source.text != text {
            source.text = text
        }
    }

    func source(for attemptID: String) -> StreamingMarkdownSource? {
        guard activeAttemptID == attemptID else { return nil }
        return activeSource
    }

    func finish() {
        activeSource?.finishStreaming()
        activeSource = nil
        activeAttemptID = nil
    }
}

// MARK: - Presentation

private struct DeepSwiftMarkdownPresentation: ViewModifier {
    func body(content: Content) -> some View {
        content
            .markdownBaseURL(MarkdownRouting.baseURL)
            .markdownMathRenderingEnabled()
            .markdownCodeBlockStyle(.default(lightTheme: "xcode", darkTheme: "dark"))
            .markdownBlockQuoteStyle(.github)
            .markdownTableStyle(.github)
            .markdownListIndent(16)
            .markdownElementRenderer(
                .link(HostFileMarkdownLinkRenderer(), urlScheme: MarkdownRouting.fileScheme)
            )
            .markdownElementRenderer(
                .link(HostFileMarkdownLinkRenderer(), urlScheme: "file")
            )
            .markdownElementRenderer(
                .image(SafeMarkdownImageRenderer(), urlScheme: "https")
            )
            .markdownElementRenderer(
                .image(SafeMarkdownImageRenderer(), urlScheme: "http")
            )
            .markdownElementRenderer(
                .image(SafeMarkdownImageRenderer(), urlScheme: "file")
            )
    }
}

private extension View {
    func deepSwiftMarkdownPresentation() -> some View {
        modifier(DeepSwiftMarkdownPresentation())
    }
}

enum MarkdownRouting {
    /// Relative links use a private URL scheme. It carries no network or file
    /// authority; the application routes it through its `openURL` handler into
    /// the Host-scoped workspace preview.
    static let fileScheme = "dsh-file"
    static let baseURL = URL(string: "dsh-file:///")!

    /// Converts a package-resolved relative link back to a workspace-relative
    /// path. The private scheme never reaches the network or AppKit's file
    /// opener directly.
    static func workspacePath(from url: URL) -> String {
        let raw = url.path.isEmpty ? url.relativeString : url.path
        let path = raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
        return path.removingPercentEncoding ?? path
    }
}

// MARK: - Links

/// Routes workspace-relative Markdown links through the application's
/// `openURL` environment, which opens them in the Host-scoped file preview.
private struct HostFileMarkdownLinkRenderer: MarkdownLinkRenderer {
    func makeBody(configuration: Configuration) -> some View {
        HostFileMarkdownLink(configuration: configuration)
    }
}

private struct HostFileMarkdownLink: View {
    let configuration: MarkdownLinkRendererConfiguration
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(configuration.url)
        } label: {
            configuration.label
                .foregroundStyle(.tint)
                .underline()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the file in the DeepSwift workspace preview")
    }
}

// MARK: - Images

/// Parses image syntax but never fetches it implicitly. Opening is a deliberate
/// user action: local workspace images use the Host preview, remote images use
/// the system browser. This keeps streamed model output from probing the local
/// filesystem or private network resources.
private struct SafeMarkdownImageRenderer: MarkdownImageRenderer {
    func makeBody(configuration: Configuration) -> some View {
        SafeMarkdownImage(configuration: configuration)
    }
}

private struct SafeMarkdownImage: View {
    let configuration: MarkdownImageRendererConfiguration
    @Environment(\.openURL) private var openURL

    private var label: String {
        let alternative = configuration.alternativeText?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return alternative.isEmpty ? "Image" : alternative
    }

    private var target: URL {
        configuration.url
    }

    private var isWorkspaceFile: Bool {
        configuration.url.scheme == MarkdownRouting.fileScheme
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
            Text(label)
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button(isWorkspaceFile ? "Preview" : "Open") {
                openURL(target)
            }
            .buttonStyle(.link)
            .font(.callout)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Image: \(label)")
    }
}

#if DEBUG
#Preview("Markdown Content v2") {
    ScrollView {
        MarkdownTextView(
            text: """
            # Native Markdown

            A paragraph with **bold**, *italic*, `inline code`, a [local file](Sources/App.swift), and an [external link](https://example.com). 中文与 emoji 混排 🚀。

            > A quoted paragraph with a nested emphasis: **still readable**.

            1. First ordered item
               - Nested bullet with `code`
               - Another nested bullet
            2. Second ordered item

            | Feature | Status |
            |---|---|
            | Headings | Supported |
            | Tables | Supported |

            ![A remote image](https://example.com/diagram.png)

            Inline math $E = mc^2$ and display math:

            $$
            \\int_0^1 x^2\\,dx = \\frac{1}{3}
            $$

            ```swift
            struct Greeting {
                func welcome(_ name: String) -> String {
                    "Hello, \\(name)!"
                }
            }
            ```

            ### Incomplete fence

            ```swift
            let inProgress = true
            """
        )
        .padding(24)
        .frame(maxWidth: 700, alignment: .leading)
    }
    .frame(width: 720, height: 900)
}

private struct StreamingMarkdownPreview: View {
    @State private var source: StreamingMarkdownSource

    init() {
        let source = StreamingMarkdownSource(
            """
            # Streaming response

            The completed stream uses the same parser and presentation as a
            historical response, including **emphasis**, `inline code`, and:

            - A list item
            - Another item

            | A | B |
            |---|---|
            | 1 | 2 |

            ```swift
            let answer = 42
            print(answer)
            ```

            Done — 中文 and emoji 🎉.
            """
        )
        source.finishStreaming()
        _source = State(initialValue: source)
    }

    var body: some View {
        ScrollView {
            StreamingMarkdownReader(source) { parseResult in
                MarkdownText(parseResult)
                    .deepSwiftMarkdownPresentation()
            }
            .padding(24)
            .frame(maxWidth: 700, alignment: .leading)
        }
        .frame(width: 720, height: 760)
    }
}

#Preview("Streaming Markdown") {
    StreamingMarkdownPreview()
}
#endif

#if DEBUG
#Preview("Markdown Narrow") {
    ScrollView {
        MarkdownTextView(
            text: """
            ## Narrow column

            | Component | Behavior |
            |---|---|
            | Table | Wraps without losing columns |
            | Code | Scrolls horizontally |

            ```swift
            let aVeryLongLineThatMustRemainReadableInANarrowConversationColumn = "value"
            ```
            """
        )
        .padding(16)
        .frame(maxWidth: 420, alignment: .leading)
    }
    .frame(width: 440, height: 640)
}
#endif
