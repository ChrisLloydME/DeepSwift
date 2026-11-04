# Third-Party Notices

DeepSwift vendors SwiftTerm for native terminal emulation, calls the official
DeepSeek Harness packages, and uses MarkdownView (with its SwiftPM
dependencies) for conversation Markdown. A packaged Release build carries its
own Node.js runtime.

## DeepSeek Harness

- Project: https://github.com/deepseek-ai/deepseek-harness
- Runtime package: `@deepseek-ai/dsh@0.2.1-rc.5`
- License: MIT
- Copyright: Copyright (c) 2026 DeepSeek

```text
MIT License

Copyright (c) 2026 DeepSeek

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The development runtime installs the official package and its transitive
dependencies. Those packages retain their own licenses in their package
directories. A production packaging pass must generate a complete dependency
notice bundle from the pinned runtime; this file records the primary component
and the policy.

## SwiftTerm 1.2.5

- Project: https://github.com/migueldeicaza/SwiftTerm
- Version: 1.2.5 (`e2b431dbf73f775fb4807a33e4572ffd3dc6933a`)
- License: MIT
- Vendored at `SwiftTerm/` and built as a separate dynamic framework
- Local modification: the SwiftTerm `Color` type is renamed
  `TerminalColor` to avoid colliding with SwiftUI's `Color` while preserving
  SwiftTerm's public terminal view API.
- The complete license text is retained at `SwiftTerm/LICENSE`.

Copyright (c) 2019-2022 Miguel de Icaza (https://github.com/migueldeicaza)
Copyright (c) 2017-2019, The xterm.js authors (https://github.com/xtermjs/xterm.js)
Copyright (c) 2014-2016, SourceLair Private Company (https://www.sourcelair.com)
Copyright (c) 2012-2013, Christopher Jeffrey (https://github.com/chjj/)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## MarkdownView 3.0.0 and transitive packages

Markdown parsing, streaming reads, tables, code blocks, math, links, and the
text-based presentation are provided by
[LiYanan2004/MarkdownView](https://github.com/LiYanan2004/MarkdownView) at the
tagged release `3.0.0` (commit `6f452b55635246224a3329362e4e11cd3d592a30`).
`DeepSwift.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
pins it and these transitive versions:

| Package | Version | License | Copyright |
|---|---|---|---|
| MarkdownView | 3.0.0 | MIT | Copyright (c) 2022 LiYanan2004 |
| Highlightr | 2.3.0 | MIT | Copyright (c) 2016 Juan Pablo Illanes |
| SwiftMath | 1.7.3 | MIT | Copyright (c) 2023 Computer Inspirations |
| RichText | 1.0.0 | MIT | Copyright (c) 2025 LiYanan2004 |
| swift-markdown | 0.9.0 | Apache License 2.0 | Copyright (c) 2021 Apple Inc. and the Swift project authors |
| swift-cmark | 0.9.0 | BSD 2-Clause | Copyright (c) 2014 John MacFarlane |

The complete MIT, Apache 2.0, and BSD 2-Clause texts, plus the swift-markdown
`NOTICE`, are bundled at
`DeepSwift/ThirdPartyLicenses-MarkdownView.txt` and copied into the app
bundle as a resource.

MarkdownView's `MarkdownText` presentation uses RichText for continuous native
text selection. Highlightr supplies fenced-code syntax colors; SwiftMath
supplies LaTeX math rendering; swift-markdown (and its cmark fork) supplies the
parser. MarkdownView's default remote-image renderer is not used: DeepSwift
installs safe image renderers that never fetch while rendering. Remote images
render as click-to-open placeholders that use the system browser. Relative image
destinations are not fetched; MarkdownView's relative-image path may show a
non-loaded placeholder. Workspace file links are routed separately through the
Host-scoped preview.

## Node.js

- Project: https://nodejs.org
- License: MIT, with bundled third-party components under their own licenses
- Usage: packaged Release builds carry `Contents/Resources/Node/bin/node` and
  Node's `LICENSE`; Debug builds may use an isolated project-local Node

`Scripts/package-runtime.sh` copies the Node license and bundled notices from
the selected official runtime.

## Other packages evaluated but not adopted

| Candidate | License | Reason not adopted |
|---|---|---|
| `gonzalezreal/textual` | MIT | MarkdownView provides the required streaming and continuous-selection surface |
| `CodeEditApp/CodeEditTextView` | MIT | Workspace text preview uses standard text views |
| `sindresorhus/KeyboardShortcuts` | MIT | Native SwiftUI commands cover the current shortcuts |
| Sparkle 2 | MIT | Not authorized for this task; no update feed |

If any candidate is adopted later, its license and attribution must be added
here and to the packaged notices before release.
