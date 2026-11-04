# DeepSwiftDiffKit

A standalone, native macOS Diff presentation package for DeepSwift. It is
deliberately not integrated with the DeepSwift application UI yet.

## Targets

- **DiffCore** — pure Foundation models, parsing, row generation, alignment,
  statistics, syntax tokenization, and intraline ranges. No SwiftUI, AppKit,
  DeepSwift model, Node, or DSH dependency.
- **DiffUI** — SwiftUI/AppKit presentation: compact summary card, native
  Unified and Side-by-Side code surfaces, and full review content.

```text
DeepSwiftDiffKit/
├── Package.swift
├── Sources/
│   ├── DiffCore/
│   │   ├── Models/
│   │   ├── Parsing/
│   │   ├── Alignment/
│   │   └── Highlighting/
│   └── DiffUI/
│       ├── DiffSummaryView.swift
│       ├── UnifiedDiffView.swift
│       ├── SideBySideDiffView.swift
│       ├── DiffReviewView.swift
│       ├── Components/
│       └── Support/
└── Tests/DiffCoreTests/
```

## Public API

### DiffCore

```swift
let source = DiffFileSource(
    kind: "text",
    path: "Sources/App.swift",
    display: "Sources/App.swift",
    before: true,
    after: true,
    hunks: [
        DiffHunkSource(
            oldStart: 10,
            oldLines: 2,
            newStart: 10,
            newLines: 2,
            lines: [" let title = \"Welcome\"", "-let count = 1", "+let count = 2"]
        )
    ],
    added: 1,
    deleted: 1
)

let file = DiffFile(source: source)
let document = DiffDocument(files: [file])
let unified = UnifiedDiffBuilder.rows(for: file)
let aligned = SideBySideDiffBuilder.rows(for: file)
let spans = IntralineDiffer.compare(old: "let count = 1", new: "let count = 2")
```

`DiffFileSource` mirrors the supported DSH file fields. The future application
adapter can map `WorkspaceChangedFile` / `WorkspaceFileDiff` into this type
without moving the application models into the package.

Authoritative Host `added`/`deleted` counts are retained. Counts are derived
from hunk lines only when the Host did not provide them; this fact is exposed by
`statisticsAreAuthoritative`.

Stable identities are deterministic:

- `DiffLineID(hunk:index:)`
- `UnifiedDiffRowID.hunkHeader` / `.line`
- `SideBySideDiffRowID(hunkIndex:ordinal:)`

### DiffUI

```swift
DiffSummaryView(
    summary: changeSummary,
    selectedFileID: $selectedFileID,
    onSelectFile: { file in ... },
    onReview: { ... }
)

UnifiedDiffView(
    file: file,
    selectedHunk: 0,
    configuration: .standard
)

SideBySideDiffView(
    file: file,
    selectedHunk: 0,
    configuration: .standard
)

DiffReviewView(
    document: document,
    configuration: .init(),
    initialFileID: nil,
    initialMode: .unified,
    onClose: nil
)
```

The host owns windows and navigation policy. `DiffReviewView` is content only;
it does not create a window, scene, or WindowGroup.

## Rendering Technology

The code surfaces use one read-only `NSTextView` per Diff surface inside an
`NSScrollView`, with an attributed string for syntax colors, diff tints, and
intraline highlights. This provides:

- Native selection, copying, find bar, and keyboard text behavior.
- Horizontal scrolling without wrapping (unless explicitly requested for
  Unified).
- No one-view-per-line explosion.
- Full-row diff backgrounds through a small `NSTextView` background override.
- A single logical row stream for Side-by-Side, so the columns cannot drift
  during vertical scrolling.

Unified line numbers are rendered as a fixed-width inline gutter; the same text
surface is selected and copied. Side-by-Side uses a fixed tab stop and padded
line-number cells so both sides share one visual row. This also means copied
text includes line numbers when a gutter is visible, which is a documented
limitation rather than a hidden behavior.

Intraline spans are UTF-16 `DiffTextSpan` ranges. The differ compares complete
`Character` values, uses common prefix/suffix scanning, and caps line length and
pair count. Long lines or excessive pairs are rendered without intraline marks.

### Alignment strategy

Each hunk is converted independently. Hunk headers are rows. Consecutive
deletion/addition runs are collected into separate ordered streams and paired by
position. When one side is exhausted, the remaining rows contain an empty
placeholder cell. This handles equal replacements, unequal replacements,
insertion-only and deletion-only regions, and multiple hunks without inventing
relationships between unrelated regions. Context and malformed records are
never paired with a different region.

## Syntax Highlighting

The package uses a small, dependency-free Swift/C-like lexical highlighter for
comments, strings, numbers, attributes, keywords, and capitalized type names.
It is a presentation aid, not a language parser. It intentionally does not
attempt multi-line string or nested block-comment state across Diff lines.

No new package dependencies were added. CodeEditTextView was evaluated and not
adopted: the review surface is read-only and native `NSTextView` already
provides the required selection, large-document layout, and scrolling behavior.
TextDiff was not adopted because the small intraline algorithm is independently
tested and avoids an entire UI dependency. Highlightr/MarkdownView already exist
in the application, but a transitive dependency is not safely importable by a
new package target; the native lexer avoids duplicating that dependency stack
and adding an unneeded JavaScript runtime to this package.

## File States

`DiffFile.state` distinguishes:

- `.modified`
- `.added`
- `.deleted`
- `.binary`
- `.oversized`
- `.coarse`
- `.empty`
- `.unavailable`

Raw `before`/`after` values remain available, so an added binary file is not
conflated with a modified binary file. Binary/oversized/unavailable states show
honest empty-state content rather than fabricating a comparison. A coarse file
shows its Host-provided replacement rows plus a visible coarse-comparison badge.

## Previews and Fixtures

Deterministic synthetic fixtures are in
`Sources/DiffUI/Support/DiffPreviewFixtures.swift`. They cover modified, added,
deleted, binary, oversized, unavailable, coarse, and empty files, multiple
hunks, Unicode, long lines, and unequal replacements. `#Preview` declarations
cover summary, Unified, Side-by-Side, and full review in light and dark modes.

The package is standalone, so Xcode Preview requires a host that can resolve the
local package. During development, the views were also rendered through an
`NSHostingView` snapshot harness and inspected; the harness is not part of the
package. No DSH Host or Node process is used by previews.

## Build and Test

From this directory:

```sh
swift build
swift test
```

The package uses Swift tools 6.0 with Swift 5 language mode and a macOS 15
deployment target, matching the application target. It has no external package
dependencies, so no new third-party notice is required.

## Future Integration

1. **Conversation summary**: convert the existing `WorkspaceChangesSummary` to
   `DiffChangeSummary` and render `DiffSummaryView` in place of the current
   `WorkspaceChangesCard`. The host supplies the selection binding and the
   full-review closure. No window belongs in the card.
2. **Review window**: load `WorkspaceFileDiff` values through the existing
   `AppModel.loadChangesDiff` path, adapt them to `DiffFileSource`/`DiffFile`,
   materialize one `DiffDocument`, and place `DiffReviewView` in a dedicated
   standard macOS window. Snapshot lifetime and privacy policy remain the host's
   responsibility; the Kit does not fetch or persist source or Diff data.

Neither integration is implemented in this task.

## Scope and Limitations

- No rename/move detection or invented rename metadata. The model can be
  extended later when DSH exposes explicit metadata.
- No textual patch parser or Git/libgit2 engine. Input is already-structured
  DSH hunks.
- No persistent Diff cache or historical snapshot retention.
- No application window, ChatView change, or Diff Sheet replacement.
- The Xcode preview host cannot resolve a package file that is not registered in
  the active project; the package's previews are compiled as part of the target.
- Copying a visible gutter includes its line numbers.
