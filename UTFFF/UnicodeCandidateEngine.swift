import Foundation

struct UnicodeCandidate {
    let normalizedSequence: String
    let output: String
    let display: String
    let score: Int
}

struct UnicodeEvaluation {
    let isUnicodeLike: Bool
    let normalizedInput: String
    let candidates: [UnicodeCandidate]
    let canAcceptHexContinuation: Bool
}

final class UnicodeCandidateEngine {
    private struct Token {
        let digits: String
    }

    private struct CandidateState {
        let codes: [String]
        let output: String
        let score: Int
    }

    private let hexDigits = Array("0123456789ABCDEF")
    private let maxCandidateExpansion = 4096

    func evaluate(rawInput: String) -> UnicodeEvaluation {
        guard !rawInput.isEmpty else {
            return UnicodeEvaluation(
                isUnicodeLike: false,
                normalizedInput: "",
                candidates: [],
                canAcceptHexContinuation: false
            )
        }

        guard let tokens = parseTokens(rawInput) else {
            return UnicodeEvaluation(
                isUnicodeLike: false,
                normalizedInput: rawInput,
                candidates: [],
                canAcceptHexContinuation: false
            )
        }

        let normalizedInput = tokens.map { "\\u\($0.digits)" }.joined()
        let canAcceptHexContinuation = tokens.last?.digits.count ?? 0 < 4

        var candidateStates: [CandidateState] = [CandidateState(codes: [], output: "", score: 0)]

        for (index, token) in tokens.enumerated() {
            let options = candidateOptions(for: token, isLast: index == tokens.count - 1)
            guard !options.isEmpty else {
                return UnicodeEvaluation(
                    isUnicodeLike: true,
                    normalizedInput: normalizedInput,
                    candidates: [],
                    canAcceptHexContinuation: canAcceptHexContinuation
                )
            }

            var nextStates: [CandidateState] = []
            nextStates.reserveCapacity(min(candidateStates.count * options.count, maxCandidateExpansion))

            for state in candidateStates {
                for option in options {
                    guard let scalarValue = UInt32(option.code, radix: 16),
                          let scalar = UnicodeScalar(scalarValue) else {
                        continue
                    }

                    let scalarText = String(scalar)
                    let newCodes = state.codes + [option.code]
                    let newOutput = state.output + scalarText
                    let newScore = state.score + scalarScore(scalarValue) - option.penalty

                    nextStates.append(CandidateState(codes: newCodes, output: newOutput, score: newScore))
                    if nextStates.count >= maxCandidateExpansion {
                        break
                    }
                }

                if nextStates.count >= maxCandidateExpansion {
                    break
                }
            }

            candidateStates = nextStates
            if candidateStates.isEmpty {
                break
            }
        }

        let candidates = candidateStates
            .map { state -> UnicodeCandidate in
                let sequence = state.codes.map { "\\u\($0)" }.joined()
                return UnicodeCandidate(
                    normalizedSequence: sequence,
                    output: state.output,
                    display: "\(sequence)  \(state.output)",
                    score: state.score
                )
            }
            .sorted(by: sortCandidates)

        return UnicodeEvaluation(
            isUnicodeLike: true,
            normalizedInput: normalizedInput,
            candidates: deduplicate(candidates),
            canAcceptHexContinuation: canAcceptHexContinuation
        )
    }

    private func candidateOptions(for token: Token, isLast: Bool) -> [(code: String, penalty: Int)] {
        switch token.digits.count {
        case 4:
            return [(token.digits, 0)]
        case 3:
            return hexDigits.map { ("\(token.digits)\($0)", 80) }
        case 0...2:
            if isLast {
                return []
            }
            return []
        default:
            return []
        }
    }

    private func parseTokens(_ input: String) -> [Token]? {
        let characters = Array(input)
        guard !characters.isEmpty else { return nil }

        var index = 0
        var tokens: [Token] = []

        while index < characters.count {
            let current = characters[index]

            if current == "\\" {
                index += 1
                guard index < characters.count else {
                    tokens.append(Token(digits: ""))
                    break
                }

                let next = characters[index]
                guard next == "u" || next == "U" else {
                    return nil
                }
                index += 1
            } else if current == "u" || current == "U" {
                index += 1
            } else {
                return nil
            }

            var digits = ""
            while index < characters.count, digits.count < 4 {
                let ch = characters[index]
                guard let normalizedHex = normalizedHexChar(ch) else {
                    break
                }
                digits.append(normalizedHex)
                index += 1
            }

            tokens.append(Token(digits: digits))
        }

        return tokens
    }

    private func normalizedHexChar(_ char: Character) -> Character? {
        switch char {
        case "0"..."9":
            return char
        case "a"..."f":
            return Character(String(char).uppercased())
        case "A"..."F":
            return char
        default:
            return nil
        }
    }

    private func scalarScore(_ value: UInt32) -> Int {
        switch value {
        case 0x41...0x5A: // A-Z
            return 1300
        case 0x61...0x7A: // a-z
            return 1260
        case 0x30...0x39: // digits
            return 1200
        case 0x4E00...0x9FFF: // CJK unified ideographs
            return 1150
        case 0x20:
            return 1000
        case 0x21...0x2F, 0x3A...0x40, 0x5B...0x60, 0x7B...0x7E:
            return 900
        case 0x0000...0x001F, 0x007F:
            return 0
        default:
            return 700
        }
    }

    private func sortCandidates(lhs: UnicodeCandidate, rhs: UnicodeCandidate) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        return lhs.normalizedSequence < rhs.normalizedSequence
    }

    private func deduplicate(_ candidates: [UnicodeCandidate]) -> [UnicodeCandidate] {
        var seen: Set<String> = []
        var results: [UnicodeCandidate] = []

        for candidate in candidates {
            if seen.insert(candidate.normalizedSequence).inserted {
                results.append(candidate)
            }
        }

        return results
    }
}
