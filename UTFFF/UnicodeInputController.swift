import Cocoa
import InputMethodKit

final class UnicodeInputController: IMKInputController {
    private let engine = UnicodeCandidateEngine()

    private var rawBuffer = ""
    private var evaluation = UnicodeEvaluation(
        isUnicodeLike: false,
        normalizedInput: "",
        candidates: [],
        canAcceptHexContinuation: false
    )
    private var showAllCandidates = false

    private lazy var candidateWindow: IMKCandidates = {
        let panel = IMKCandidates(server: server(), panelType: kIMKSingleColumnScrollingCandidatePanel)
        panel?.setDismissesAutomatically(false)
        panel?.setSelectionKeys([18, 19, 20, 21, 23, 22, 26, 28, 25].map { NSNumber(value: $0) })
        panel?.setAttributes([IMKCandidatesSendServerKeyEventFirst: true])
        return panel!
    }()

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        resetState()
    }

    override func deactivateServer(_ sender: Any!) {
        super.deactivateServer(sender)
        resetState()
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard event.type == .keyDown else {
            return false
        }

        if shouldIgnore(event: event) {
            return false
        }

        let keyCode = event.keyCode

        if keyCode == 53 { // Esc
            if isComposing {
                commitRawText(client: sender)
                return true
            }
            return false
        }

        if keyCode == 51 || keyCode == 117 { // delete/backspace
            return handleDelete(client: sender)
        }

        if keyCode == 49 { // space
            return commitFirstCandidate(client: sender)
        }

        if keyCode == 36 || keyCode == 76 { // return / enter
            return commitFirstCandidate(client: sender)
        }

        guard let chars = event.characters, let char = chars.first else {
            return false
        }

        if !isComposing {
            if char == "\\" || char == "u" || char == "U" {
                rawBuffer = String(char)
                showAllCandidates = false
                reevaluate()
                updateUI()
                return true
            }
            return false
        }

        if char == "+" {
            showAllCandidates = true
            updateUI()
            return true
        }

        if shouldSelectByNumber(char: char) {
            return selectCandidateByNumber(char: char, client: sender)
        }

        if isAcceptedCompositionCharacter(char) {
            rawBuffer.append(char)
            reevaluate()
            updateUI()
            return true
        }

        // Non-unicode text should flow through unchanged.
        commitFirstCandidate(client: sender)
        return false
    }

    override func candidates(_ sender: Any!) -> [Any]! {
        visibleCandidates.map { $0.display }
    }

    override func candidateSelected(_ candidateString: NSAttributedString!) {
        guard let value = candidateString?.string,
              let match = visibleCandidates.first(where: { $0.display == value }) else {
            return
        }

        commitOutput(match.output)
    }

    override func commitComposition(_ sender: Any!) {
        if !rawBuffer.isEmpty {
            _ = commitFirstCandidate(client: sender)
        } else {
            resetState()
        }
    }

    override func composedString(_ sender: Any!) -> Any! {
        rawBuffer
    }

    override func originalString(_ sender: Any!) -> NSAttributedString! {
        NSAttributedString(string: rawBuffer)
    }

    private var isComposing: Bool {
        !rawBuffer.isEmpty
    }

    private var visibleCandidates: [UnicodeCandidate] {
        if showAllCandidates {
            return evaluation.candidates
        }
        return Array(evaluation.candidates.prefix(8))
    }

    private func reevaluate() {
        evaluation = engine.evaluate(rawInput: rawBuffer)
        if !evaluation.isUnicodeLike {
            evaluation = UnicodeEvaluation(
                isUnicodeLike: false,
                normalizedInput: rawBuffer,
                candidates: [],
                canAcceptHexContinuation: false
            )
        }
    }

    private func updateUI() {
        updateComposition()

        let candidates = visibleCandidates
        if candidates.isEmpty {
            candidateWindow.hide()
            return
        }

        candidateWindow.setCandidateData(candidates.map { $0.display })
        candidateWindow.update()
        candidateWindow.show(kIMKLocateCandidatesBelowHint)
    }

    private func shouldIgnore(event: NSEvent) -> Bool {
        let forbidden: NSEvent.ModifierFlags = [.command, .control, .option]
        return !event.modifierFlags.intersection(forbidden).isEmpty
    }

    private func isAcceptedCompositionCharacter(_ char: Character) -> Bool {
        if char == "\\" || char == "u" || char == "U" {
            return true
        }

        switch char {
        case "0"..."9", "a"..."f", "A"..."F":
            return true
        default:
            return false
        }
    }

    private func shouldSelectByNumber(char: Character) -> Bool {
        guard ("1"..."9").contains(char) else {
            return false
        }

        // Numeric keys are reserved for hex continuation when the current token is still incomplete.
        if evaluation.canAcceptHexContinuation {
            return false
        }

        return !visibleCandidates.isEmpty
    }

    private func selectCandidateByNumber(char: Character, client: Any!) -> Bool {
        guard let digit = Int(String(char)) else {
            return false
        }

        let index = digit - 1
        let candidates = visibleCandidates
        guard index >= 0, index < candidates.count else {
            return false
        }

        commitOutput(candidates[index].output, client: senderClient(from: client))
        return true
    }

    private func handleDelete(client: Any!) -> Bool {
        guard isComposing else {
            return false
        }

        rawBuffer.removeLast()
        showAllCandidates = false

        if rawBuffer.isEmpty {
            resetState()
            return true
        }

        reevaluate()
        updateUI()
        return true
    }

    private func commitFirstCandidate(client: Any!) -> Bool {
        if !visibleCandidates.isEmpty {
            commitOutput(visibleCandidates[0].output, client: senderClient(from: client))
        } else {
            commitRawText(client: client)
        }
        return true
    }

    private func commitRawText(client: Any!) {
        insertText(rawBuffer, client: senderClient(from: client))
        resetState()
    }

    private func commitOutput(_ output: String) {
        commitOutput(output, client: client())
    }

    private func commitOutput(_ output: String, client: (any IMKTextInput & NSObjectProtocol)?) {
        insertText(output, client: client)
        resetState()
    }

    private func insertText(_ text: String, client: (any IMKTextInput & NSObjectProtocol)?) {
        client?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    private func senderClient(from sender: Any!) -> (any IMKTextInput & NSObjectProtocol)? {
        sender as? (any IMKTextInput & NSObjectProtocol)
    }

    private func resetState() {
        rawBuffer = ""
        evaluation = UnicodeEvaluation(
            isUnicodeLike: false,
            normalizedInput: "",
            candidates: [],
            canAcceptHexContinuation: false
        )
        showAllCandidates = false
        candidateWindow.hide()
    }
}
