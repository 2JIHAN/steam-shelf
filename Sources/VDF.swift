import Foundation

/// Steam의 KeyValues(VDF) 텍스트 포맷 파서.
/// `"key" "value"` 와 `"key" { ... }` 두 형태만 다루면 충분하다.
indirect enum VDFNode {
    case string(String)
    case object([String: VDFNode])

    subscript(key: String) -> VDFNode? {
        guard case .object(let dict) = self else { return nil }
        // Steam은 키 대소문자를 일관되게 쓰지 않는다.
        if let hit = dict[key] { return hit }
        let lowered = key.lowercased()
        return dict.first { $0.key.lowercased() == lowered }?.value
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var children: [String: VDFNode] {
        if case .object(let dict) = self { return dict }
        return [:]
    }
}

enum VDF {
    static func parse(_ text: String) -> VDFNode {
        var scanner = Scanner(text)
        return .object(scanner.parseObjectBody(isRoot: true))
    }

    static func parse(contentsOf url: URL) -> VDFNode? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        guard let text else { return nil }
        return parse(text)
    }

    private struct Scanner {
        let chars: [Character]
        var i = 0

        init(_ text: String) { chars = Array(text) }

        mutating func parseObjectBody(isRoot: Bool = false) -> [String: VDFNode] {
            var result: [String: VDFNode] = [:]
            while true {
                skipTrivia()
                guard i < chars.count else { break }
                if chars[i] == "}" {
                    if !isRoot { i += 1 }
                    break
                }
                guard let key = readToken() else { break }
                skipTrivia()
                guard i < chars.count else {
                    result[key] = .string("")
                    break
                }
                if chars[i] == "{" {
                    i += 1
                    result[key] = .object(parseObjectBody())
                } else if let value = readToken() {
                    result[key] = .string(value)
                }
            }
            return result
        }

        mutating func skipTrivia() {
            while i < chars.count {
                let c = chars[i]
                if c.isWhitespace {
                    i += 1
                } else if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                    while i < chars.count, chars[i] != "\n" { i += 1 }
                } else {
                    return
                }
            }
        }

        mutating func readToken() -> String? {
            skipTrivia()
            guard i < chars.count else { return nil }
            if chars[i] == "\"" {
                i += 1
                var out = ""
                while i < chars.count {
                    let c = chars[i]
                    if c == "\\", i + 1 < chars.count {
                        let next = chars[i + 1]
                        switch next {
                        case "n": out.append("\n")
                        case "t": out.append("\t")
                        default: out.append(next)
                        }
                        i += 2
                    } else if c == "\"" {
                        i += 1
                        return out
                    } else {
                        out.append(c)
                        i += 1
                    }
                }
                return out
            }
            // 따옴표 없는 토큰
            var out = ""
            while i < chars.count, !chars[i].isWhitespace, chars[i] != "{", chars[i] != "}" {
                out.append(chars[i])
                i += 1
            }
            return out.isEmpty ? nil : out
        }
    }
}
