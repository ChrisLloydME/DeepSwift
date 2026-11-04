//
//  SwiftSyntaxHighlighter.swift
//  DiffCore
//

import Foundation

public enum DiffSyntaxTokenKind: String, Hashable, Sendable, CaseIterable {
    case keyword
    case type
    case string
    case comment
    case number
    case attribute
}

public struct DiffSyntaxToken: Hashable, Sendable {
    public let kind: DiffSyntaxTokenKind
    public let span: DiffTextSpan

    public init(kind: DiffSyntaxTokenKind, span: DiffTextSpan) {
        self.kind = kind
        self.span = span
    }
}

/// A lightweight, dependency-free Swift lexer used only for code color.
///
/// This is intentionally a presentation aid, not a Swift compiler parser. It
/// recognizes the high-value lexical categories (comments, strings, numbers,
/// attributes, keywords, and capitalized type names) and degrades to plain
/// text for syntax it does not understand. Multi-line strings and nested block
/// comments are not interpreted across diff lines.
public enum SwiftSyntaxHighlighter {
    private static let keywords: Set<String> = [
        "actor", "any", "as", "associatedtype", "async", "await", "break",
        "case", "catch", "class", "continue", "convenience", "defer", "deinit",
        "do", "dynamic", "else", "enum", "extension", "fallthrough", "fileprivate",
        "final", "for", "func", "get", "guard", "if", "import", "in", "indirect",
        "init", "inout", "internal", "is", "isolated", "lazy", "let", "mutating",
        "nonisolated", "open", "operator", "override", "private", "protocol",
        "public", "repeat", "required", "rethrows", "return", "self", "set",
        "some", "static", "struct", "subscript", "super", "switch", "throw",
        "throws", "try", "typealias", "unsafe", "var", "where", "while", "willSet"
    ]

    public static func tokens(in line: String) -> [DiffSyntaxToken] {
        let characters = Array(line)
        var tokens: [DiffSyntaxToken] = []
        var index = 0
        var offsets = [0]
        offsets.reserveCapacity(characters.count + 1)
        for character in characters {
            offsets.append(offsets[offsets.count - 1] + character.utf16.count)
        }

        func append(_ kind: DiffSyntaxTokenKind, from start: Int, to end: Int) {
            guard end > start else { return }
            let location = offsets[start]
            let length = offsets[end] - location
            guard length > 0 else { return }
            tokens.append(DiffSyntaxToken(
                kind: kind,
                span: DiffTextSpan(location: location, length: length)
            ))
        }

        while index < characters.count {
            let character = characters[index]

            if character == "/", index + 1 < characters.count, characters[index + 1] == "/" {
                append(.comment, from: index, to: characters.count)
                break
            }

            if character == "/", index + 1 < characters.count, characters[index + 1] == "*" {
                let start = index
                index += 2
                while index + 1 < characters.count,
                      !(characters[index] == "*" && characters[index + 1] == "/") {
                    index += 1
                }
                index = min(characters.count, index + 2)
                append(.comment, from: start, to: index)
                continue
            }

            if character == "\"" {
                let start = index
                index += 1
                var escaped = false
                while index < characters.count {
                    let current = characters[index]
                    if escaped {
                        escaped = false
                    } else if current == "\\" {
                        escaped = true
                    } else if current == "\"" {
                        index += 1
                        break
                    }
                    index += 1
                }
                append(.string, from: start, to: index)
                continue
            }

            if character == "@" {
                let start = index
                index += 1
                while index < characters.count, isIdentifierCharacter(characters[index]) {
                    index += 1
                }
                append(.attribute, from: start, to: index)
                continue
            }

            if character.isNumber {
                let start = index
                index += 1
                while index < characters.count,
                      characters[index].isHexDigit || characters[index] == "." || characters[index] == "_" {
                    index += 1
                }
                append(.number, from: start, to: index)
                continue
            }

            if isIdentifierStart(character) {
                let start = index
                index += 1
                while index < characters.count, isIdentifierCharacter(characters[index]) {
                    index += 1
                }
                let word = String(characters[start..<index])
                if keywords.contains(word) {
                    append(.keyword, from: start, to: index)
                } else if word.first?.isUppercase == true {
                    append(.type, from: start, to: index)
                }
                continue
            }

            index += 1
        }

        return tokens
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.isLetter
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }


}
