import AppKit

enum ImageLinkFormatter {
    static func string(for image: UploadedImage, asMarkdown: Bool) -> String {
        guard asMarkdown else { return image.url }
        // Keep stored text intact; paragraph breaks become spaces in image alt text.
        let text = (image.caption ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines).joined(separator: " ")
        let punctuation = CharacterSet(charactersIn: "\\`*_{}[]<>()!#&")
        let alt = text.unicodeScalars.map { punctuation.contains($0) ? "\\" + String($0) : String($0) }.joined()
        let destination = image.url.unicodeScalars.map { scalar -> String in
            if CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar == "<" || scalar == ">" {
                return String(scalar).utf8.map { String(format: "%%%02X", $0) }.joined()
            }
            return "\\()".unicodeScalars.contains(scalar) ? "\\" + String(scalar) : String(scalar)
        }.joined()
        return "![\(alt)](\(destination))"
    }
}

/// Both automatic and history copies use the same formatter and write boundary.
@MainActor
struct LinkClipboard {
    let pasteboard: NSPasteboard
    let playSuccessSound: @MainActor () -> Void

    init(pasteboard: NSPasteboard = .general,
         playSuccessSound: @escaping @MainActor () -> Void = { NotificationManager.shared.playSuccessSound() }) {
        self.pasteboard = pasteboard
        self.playSuccessSound = playSuccessSound
    }

    @discardableResult
    func copy(_ image: UploadedImage, asMarkdown: Bool, playSound: Bool) -> Bool {
        let text = ImageLinkFormatter.string(for: image, asMarkdown: asMarkdown)
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { return false }
        if playSound { playSuccessSound() }
        return true
    }
}
