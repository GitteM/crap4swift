import Foundation

/// Extracts concrete Swift functions and estimates their cyclomatic complexity.
///
/// This is a token-based scanner rather than a full Swift AST parser. It:
///
/// - blanks out comments and string literals (preserving line breaks) so that
///   keywords appearing inside them are not counted
/// - finds `func` declarations that have a body (protocol requirements and
///   other body-less declarations are ignored, as are `init`/`deinit`/`subscript`)
/// - ignores functions declared inside another function body
/// - counts decision points inside the body: `if`, `guard`, `for`, `while`
///   (including the `while` of a `repeat`/`while` loop), `catch`,
///   `case`/`default`, `&&`, `||`, `??` and ternaries
///
/// It intentionally mirrors the estimate-oriented behavior of `crap4java`.
enum SwiftMethodParser {

    struct Token {
        let text: String
        let line: Int
    }

    static func parse(_ source: String) -> [MethodDescriptor] {
        let cleaned = stripCommentsAndStrings(source)
        let tokens = tokenize(cleaned)
        let braceMatch = matchBraces(tokens)
        let types = collectTypes(tokens, braceMatch: braceMatch)

        var methods: [MethodDescriptor] = []
        var index = 0
        while index < tokens.count {
            if tokens[index].text == "func",
               let function = parseFunction(tokens, at: index, braceMatch: braceMatch) {
                let enclosing = innermostType(types, containing: index)
                methods.append(MethodDescriptor(
                    name: function.name,
                    startLine: tokens[index].line,
                    endLine: function.endLine,
                    complexity: function.complexity,
                    enclosingType: enclosing
                ))
                index = function.bodyClose + 1
                continue
            }
            index += 1
        }
        return methods
    }

    // MARK: - Function scanning

    private struct ParsedFunction {
        let name: String
        let endLine: Int
        let complexity: Int
        let bodyClose: Int
    }

    private static func parseFunction(_ tokens: [Token],
                                      at index: Int,
                                      braceMatch: [Int: Int]) -> ParsedFunction? {
        guard let nameIndex = nextIdentifier(tokens, after: index) else {
            return nil
        }
        let name = tokens[nameIndex].text

        guard let openParen = nextToken(tokens, after: nameIndex, text: "(") else {
            return nil
        }
        guard let closeParen = matchingParen(tokens, open: openParen) else {
            return nil
        }

        var cursor = closeParen + 1
        while cursor < tokens.count {
            let text = tokens[cursor].text
            if text == "{" {
                guard let close = braceMatch[cursor] else {
                    return nil
                }
                let complexity = computeComplexity(tokens, from: cursor + 1, to: close - 1)
                return ParsedFunction(
                    name: name,
                    endLine: tokens[close].line,
                    complexity: complexity,
                    bodyClose: close
                )
            }
            if text == ";" || text == "}" {
                return nil
            }
            if isDeclarationKeyword(text) {
                return nil
            }
            cursor += 1
        }
        return nil
    }

    static func computeComplexity(_ tokens: [Token], from start: Int, to end: Int) -> Int {
        var complexity = 1
        var index = start
        while index <= end && index < tokens.count {
            let text = tokens[index].text
            switch text {
            case "if", "guard", "for", "while", "catch":
                complexity += 1
            case "case", "default":
                complexity += 1
            case "&&", "||", "??":
                complexity += 1
            case "?":
                if isTernary(tokens, at: index) {
                    complexity += 1
                }
            default:
                break
            }
            index += 1
        }
        return complexity
    }

    /// A `?` counts as a ternary only when it is followed by the start of an
    /// expression and a matching `:` appears later on the same source line.
    /// This avoids mistaking optional type syntax (`Int?`) for a ternary.
    static func isTernary(_ tokens: [Token], at index: Int) -> Bool {
        guard index > 0, index + 1 < tokens.count else {
            return false
        }
        if tokens[index - 1].text == "?" {
            return false
        }
        guard startsExpression(tokens[index + 1].text) else {
            return false
        }
        let line = tokens[index].line
        var cursor = index + 1
        while cursor < tokens.count && tokens[cursor].line == line {
            let text = tokens[cursor].text
            if text == ":" {
                return true
            }
            if text == ";" || text == "{" || text == "}" {
                return false
            }
            cursor += 1
        }
        return false
    }

    // MARK: - Complexity helpers

    private static func startsExpression(_ text: String) -> Bool {
        switch text {
        case "(", "[", "!", "-", "+", "nil", "true", "false", "self", "try", "#":
            return true
        default:
            break
        }
        guard let first = text.first, first.isLetter || first == "_" || first.isNumber else {
            return false
        }
        return !isDeclarationKeyword(text)
    }

    private static let typeKeywords: Set<String> = [
        "struct", "class", "enum", "actor", "extension", "protocol"
    ]

    private static let declarationKeywords: Set<String> = [
        "func", "var", "let", "class", "struct", "enum", "extension", "protocol",
        "actor", "init", "deinit", "subscript", "case", "default", "import",
        "typealias", "associatedtype", "operator", "static", "private",
        "fileprivate", "internal", "public", "open", "final", "override",
        "mutating", "nonmutating", "convenience", "required", "dynamic",
        "indirect", "prefix", "postfix", "infix", "lazy", "weak", "unowned",
        "defer", "guard", "if", "else", "for", "while", "repeat", "switch",
        "return", "break", "continue", "fallthrough", "throw", "throws",
        "rethrows", "async", "await", "in", "where", "do", "try", "catch",
        "some", "any", "self", "Self", "super", "nil", "true", "false",
        "is", "as", "get", "set", "willSet", "didSet", "newValue", "oldValue"
    ]

    static func isDeclarationKeyword(_ text: String) -> Bool {
        declarationKeywords.contains(text)
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_"
    }

    private static func nextIdentifier(_ tokens: [Token], after index: Int) -> Int? {
        var cursor = index + 1
        while cursor < tokens.count {
            guard let first = tokens[cursor].text.first,
                  isIdentifierStart(first) || first == "`" else {
                cursor += 1
                continue
            }
            return cursor
        }
        return nil
    }

    private static func nextToken(_ tokens: [Token], after index: Int, text: String) -> Int? {
        var cursor = index + 1
        while cursor < tokens.count {
            if tokens[cursor].text == text {
                return cursor
            }
            cursor += 1
        }
        return nil
    }

    private static func matchingParen(_ tokens: [Token], open: Int) -> Int? {
        var depth = 0
        var cursor = open
        while cursor < tokens.count {
            switch tokens[cursor].text {
            case "(":
                depth += 1
            case ")":
                depth -= 1
                if depth == 0 {
                    return cursor
                }
            default:
                break
            }
            cursor += 1
        }
        return nil
    }

    // MARK: - Type declarations

    static func collectTypes(_ tokens: [Token],
                             braceMatch: [Int: Int]) -> [(name: String, open: Int, close: Int)] {
        var types: [(name: String, open: Int, close: Int)] = []
        for index in tokens.indices where typeKeywords.contains(tokens[index].text) {
            guard let nameIndex = nextIdentifier(tokens, after: index) else {
                continue
            }
            let name = tokens[nameIndex].text
            if isDeclarationKeyword(name) {
                continue
            }
            guard let open = nextToken(tokens, after: nameIndex, text: "{"),
                  let close = braceMatch[open] else {
                continue
            }
            types.append((name: name, open: open, close: close))
        }
        return types
    }

    private static func innermostType(_ types: [(name: String, open: Int, close: Int)],
                                      containing index: Int) -> String? {
        var best: (name: String, open: Int)?
        for type in types where type.open < index && index < type.close {
            if best == nil || type.open > best!.open {
                best = (type.name, type.open)
            }
        }
        return best?.name
    }

    // MARK: - Brace matching

    static func matchBraces(_ tokens: [Token]) -> [Int: Int] {
        var map: [Int: Int] = [:]
        var stack: [Int] = []
        for index in tokens.indices {
            switch tokens[index].text {
            case "{":
                stack.append(index)
            case "}":
                if let open = stack.popLast() {
                    map[open] = index
                }
            default:
                break
            }
        }
        return map
    }

    // MARK: - Lexing

    private static let operatorCharacters: Set<Character> = Set("&=|?.,!-+*/%<>^~")

    static func tokenize(_ source: String) -> [Token] {
        var tokens: [Token] = []
        let characters = Array(source)
        var index = 0
        var line = 1
        let count = characters.count

        while index < count {
            let character = characters[index]
            if character == "\n" {
                line += 1
                index += 1
                continue
            }
            if character.isWhitespace {
                index += 1
                continue
            }

            if character.isLetter || character == "_" || character == "`" {
                var end = index
                if character == "`" {
                    end += 1
                    while end < count && characters[end] != "`" {
                        end += 1
                    }
                    if end < count {
                        end += 1
                    }
                } else {
                    while end < count && (characters[end].isLetter || characters[end].isNumber || characters[end] == "_") {
                        end += 1
                    }
                }
                tokens.append(Token(text: String(characters[index..<end]), line: line))
                index = end
                continue
            }

            if character.isNumber {
                var end = index
                while end < count && (characters[end].isNumber || characters[end] == "." || characters[end].isLetter || characters[end] == "_") {
                    end += 1
                }
                tokens.append(Token(text: String(characters[index..<end]), line: line))
                index = end
                continue
            }

            if operatorCharacters.contains(character) {
                var end = index
                while end < count && operatorCharacters.contains(characters[end]) {
                    end += 1
                }
                tokens.append(Token(text: String(characters[index..<end]), line: line))
                index = end
                continue
            }

            tokens.append(Token(text: String(character), line: line))
            index += 1
        }
        return tokens
    }

    /// Replaces comment and string-literal characters with spaces while
    /// preserving line breaks so line numbers remain accurate.
    static func stripCommentsAndStrings(_ source: String) -> String {
        var output = ""
        let characters = Array(source)
        var index = 0
        let count = characters.count

        while index < count {
            let character = characters[index]

            if character == "/" && index + 1 < count && characters[index + 1] == "/" {
                while index < count && characters[index] != "\n" {
                    output.append(" ")
                    index += 1
                }
                continue
            }

            if character == "/" && index + 1 < count && characters[index + 1] == "*" {
                var depth = 1
                output += "  "
                index += 2
                while index < count && depth > 0 {
                    if characters[index] == "\n" {
                        output.append("\n")
                        index += 1
                        continue
                    }
                    if characters[index] == "/" && index + 1 < count && characters[index + 1] == "*" {
                        depth += 1
                        output += "  "
                        index += 2
                        continue
                    }
                    if characters[index] == "*" && index + 1 < count && characters[index + 1] == "/" {
                        depth -= 1
                        output += "  "
                        index += 2
                        continue
                    }
                    output.append(" ")
                    index += 1
                }
                continue
            }

            if character == "\"" {
                let isMultiline = index + 2 < count && characters[index + 1] == "\"" && characters[index + 2] == "\""
                if isMultiline {
                    output += "   "
                    index += 3
                    while index < count {
                        if characters[index] == "\\" && index + 1 < count {
                            output += "  "
                            index += 2
                            continue
                        }
                        if characters[index] == "\"",
                           index + 2 < count,
                           characters[index + 1] == "\"",
                           characters[index + 2] == "\"" {
                            output += "   "
                            index += 3
                            break
                        }
                        if characters[index] == "\n" {
                            output.append("\n")
                        } else {
                            output.append(" ")
                        }
                        index += 1
                    }
                } else {
                    output.append(" ")
                    index += 1
                    while index < count {
                        if characters[index] == "\\" && index + 1 < count {
                            output += "  "
                            index += 2
                            continue
                        }
                        if characters[index] == "\"" {
                            output.append(" ")
                            index += 1
                            break
                        }
                        if characters[index] == "\n" {
                            output.append("\n")
                        } else {
                            output.append(" ")
                        }
                        index += 1
                    }
                }
                continue
            }

            output.append(character)
            index += 1
        }
        return output
    }
}
