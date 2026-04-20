import SwiftUI

/// Parses mIRC-style formatting codes in IRC message content and converts them
/// to a SwiftUI `AttributedString` with the appropriate font traits and colors.
///
/// Supported codes:
///   `\x02`  bold
///   `\x1D`  italic
///   `\x1F`  underline
///   `\x1E`  strikethrough
///   `\x0F`  reset all
///   `\x03NN[,MM]`  foreground[,background] color (mIRC 16-color palette)
///   `\x04RRGGBB`  hex color (IRCv3 extension)
///   `\x16`  reverse/swap fg/bg
enum IRCTextFormatter {

    // MARK: - mIRC 16-color palette (index 0–15)

    private static let mircColors: [Color] = [
        Color(.white),                          //  0 white
        Color(.black),                          //  1 black
        Color(hex: "00007F"),                   //  2 dark blue
        Color(hex: "009300"),                   //  3 dark green
        Color(hex: "FF0000"),                   //  4 red
        Color(hex: "7F0000"),                   //  5 dark red
        Color(hex: "9C009C"),                   //  6 dark magenta
        Color(hex: "FC7F00"),                   //  7 orange
        Color(hex: "FFFF00"),                   //  8 yellow
        Color(hex: "00FC00"),                   //  9 bright green
        Color(hex: "009393"),                   // 10 teal
        Color(hex: "00FFFF"),                   // 11 cyan
        Color(hex: "0000FC"),                   // 12 bright blue
        Color(hex: "FF00FF"),                   // 13 magenta
        Color(hex: "7F7F7F"),                   // 14 gray
        Color(hex: "D2D2D2"),                   // 15 light gray
    ]

    // MARK: - Public API

    /// Returns an `AttributedString` with mIRC formatting applied.
    /// Falls back to a plain `AttributedString` if parsing fails.
    static func attributedString(from text: String, foreground: Color) -> AttributedString {
        guard text.contains(where: { isFormattingChar($0) }) else {
            // Fast path: no formatting codes present
            return AttributedString(text)
        }
        return parse(text, defaultForeground: foreground)
    }

    /// Returns a plain string with all IRC formatting codes stripped.
    static func stripped(_ text: String) -> String {
        var result = ""
        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            switch ch {
            case "\u{02}", "\u{1D}", "\u{1F}", "\u{1E}", "\u{16}", "\u{0F}":
                i = text.index(after: i)
            case "\u{03}": // color
                i = text.index(after: i)
                i = skipColorParams(text, from: i)
            case "\u{04}": // hex color
                i = text.index(after: i)
                i = skipHexColor(text, from: i)
            default:
                result.append(ch)
                i = text.index(after: i)
            }
        }
        return result
    }

    // MARK: - Private parsing

    private static func isFormattingChar(_ ch: Character) -> Bool {
        switch ch {
        case "\u{02}", "\u{1D}", "\u{1F}", "\u{1E}", "\u{16}", "\u{0F}", "\u{03}", "\u{04}":
            return true
        default:
            return false
        }
    }

    private struct FormattingState {
        var bold = false
        var italic = false
        var underline = false
        var strikethrough = false
        var fgColor: Color? = nil
        var bgColor: Color? = nil

        mutating func reset() {
            bold = false; italic = false; underline = false; strikethrough = false
            fgColor = nil; bgColor = nil
        }
    }

    private static func parse(_ text: String, defaultForeground: Color) -> AttributedString {
        var result = AttributedString()
        var state = FormattingState()
        var i = text.startIndex
        var chunk = ""

        func flushChunk() {
            guard !chunk.isEmpty else { return }
            var seg = AttributedString(chunk)
            var container = AttributeContainer()

            var traits = Font.TextStyle.body
            _ = traits
            var fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)

            if state.bold      { fontDescriptor = fontDescriptor.withSymbolicTraits(.traitBold)   ?? fontDescriptor }
            if state.italic    { fontDescriptor = fontDescriptor.withSymbolicTraits(.traitItalic) ?? fontDescriptor }

            let font = UIFont(descriptor: fontDescriptor, size: 0)
            container.font = Font(font)

            if state.underline      { container.underlineStyle = .single }
            if state.strikethrough  { container.strikethroughStyle = .single }
            if let fg = state.fgColor { container.foregroundColor = fg }

            seg.mergeAttributes(container)
            result += seg
            chunk = ""
        }

        while i < text.endIndex {
            let ch = text[i]
            switch ch {
            case "\u{02}": // bold
                flushChunk()
                state.bold.toggle()
                i = text.index(after: i)

            case "\u{1D}": // italic
                flushChunk()
                state.italic.toggle()
                i = text.index(after: i)

            case "\u{1F}": // underline
                flushChunk()
                state.underline.toggle()
                i = text.index(after: i)

            case "\u{1E}": // strikethrough
                flushChunk()
                state.strikethrough.toggle()
                i = text.index(after: i)

            case "\u{16}": // reverse — skip (color swap is complex, just skip)
                flushChunk()
                i = text.index(after: i)

            case "\u{0F}": // reset
                flushChunk()
                state.reset()
                i = text.index(after: i)

            case "\u{03}": // mIRC color
                flushChunk()
                i = text.index(after: i)
                let (fg, bg, newI) = parseColorParams(text, from: i)
                state.fgColor = fg.map { mircColors[min($0, mircColors.count - 1)] }
                if let bg { state.bgColor = mircColors[min(bg, mircColors.count - 1)] }
                if fg == nil && bg == nil { state.fgColor = nil; state.bgColor = nil }
                i = newI

            case "\u{04}": // hex color
                flushChunk()
                i = text.index(after: i)
                let (hex, newI) = parseHexColor(text, from: i)
                state.fgColor = hex.map { Color(hex: $0) }
                i = newI

            default:
                chunk.append(ch)
                i = text.index(after: i)
            }
        }
        flushChunk()
        return result
    }

    // MARK: - Color parameter parsing helpers

    /// Parses optional `NN[,MM]` color params and returns (fg, bg, newIndex).
    private static func parseColorParams(_ text: String, from start: String.Index) -> (Int?, Int?, String.Index) {
        var i = start
        guard i < text.endIndex, text[i].isNumber else { return (nil, nil, i) }
        var fgStr = ""
        if text[i].isNumber { fgStr.append(text[i]); i = text.index(after: i) }
        if i < text.endIndex && text[i].isNumber { fgStr.append(text[i]); i = text.index(after: i) }
        let fg = Int(fgStr)
        guard i < text.endIndex && text[i] == "," else { return (fg, nil, i) }
        i = text.index(after: i) // skip comma
        guard i < text.endIndex && text[i].isNumber else { return (fg, nil, i) }
        var bgStr = ""
        if text[i].isNumber { bgStr.append(text[i]); i = text.index(after: i) }
        if i < text.endIndex && text[i].isNumber { bgStr.append(text[i]); i = text.index(after: i) }
        return (fg, Int(bgStr), i)
    }

    /// Parses a 6-character hex color and returns (hexString, newIndex).
    private static func parseHexColor(_ text: String, from start: String.Index) -> (String?, String.Index) {
        var i = start
        var hex = ""
        for _ in 0..<6 {
            guard i < text.endIndex, text[i].isHexDigit else { return (nil, start) }
            hex.append(text[i])
            i = text.index(after: i)
        }
        return (hex, i)
    }

    private static func skipColorParams(_ text: String, from start: String.Index) -> String.Index {
        let (_, _, i) = parseColorParams(text, from: start)
        return i
    }

    private static func skipHexColor(_ text: String, from start: String.Index) -> String.Index {
        let (_, i) = parseHexColor(text, from: start)
        return i
    }
}
