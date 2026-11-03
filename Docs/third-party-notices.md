# Third-Party Notices

DeepSwift vendors SwiftTerm for native terminal emulation and calls the
official DeepSeek Harness packages. In development it runs Node.js from the
host machine; a packaged build must carry its own Node.js runtime.

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

## Node.js

- Project: https://nodejs.org
- License: MIT, with bundled third-party components under their own licenses
- Usage: development runtime process host; not bundled with the current app

A future packaged build must ship a Node.js binary together with Node's
`LICENSE` and its bundled-component notices.

## Swift packages evaluated but not adopted

DeepSwift currently uses only Apple frameworks for UI, rendering, and process
management. The following candidates were considered and not added:

| Candidate | License | Reason not adopted |
|---|---|---|
| `gonzalezreal/textual` | MIT | Native Markdown block rendering was sufficient for this phase |
| `CodeEditApp/CodeEditTextView` | MIT | Workspace text preview uses standard text views |
| `migueldeicaza/SwiftTerm` | MIT | Adopted for native terminal emulation (see above) |
| `sindresorhus/KeyboardShortcuts` | MIT | Native SwiftUI commands cover the current shortcuts |
| Sparkle 2 | MIT | Packaging and update feed are not yet implemented |

If any candidate is adopted later, its license and attribution must be added
here and to the packaged notices before release.
