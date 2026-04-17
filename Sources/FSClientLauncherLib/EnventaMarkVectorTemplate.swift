import AppKit

/// Vektorgetreues Mark (`enventa-mark-cropped.svg`): dieselben drei `d`-Pfade wie in `EnventaSVGSource`, per `NSBezierPath` (ohne WebKit).
/// Weiß auf transparent, für `NSImage.isTemplate = true`.
enum EnventaMarkVectorTemplate {
    private static let viewMinX: CGFloat = -1
    private static let viewMinY: CGFloat = 2.8291
    private static let viewWidth: CGFloat = 36.0363
    private static let viewHeight: CGFloat = 33.7878

    private static let pathDs: [String] = [
        "M10.6362 3.8291H34.0363V5.28781C34.0363 8.87379 31.1189 11.7912 27.5329 11.7912C27.5329 11.7912 27.5329 11.7912 27.4721 11.7912H4.13281V10.3325C4.13281 6.74651 7.05022 3.8291 10.6362 3.8291Z",
        "M25.7104 23.7038H2.37109V22.2451C2.37109 18.6591 5.28851 15.7417 8.87449 15.7417H32.2138V17.2004C32.2138 20.7864 29.2964 23.7038 25.7104 23.7038Z",
        "M6.5034 27.6548H29.8427V29.1135C29.8427 32.6995 26.9253 35.6169 23.3393 35.6169H0V34.1582C0 30.5722 2.91741 27.6548 6.5034 27.6548Z",
    ]

    static func menuBarTemplateImage(side: CGFloat = 18) -> NSImage {
        let s = max(16, side)
        let img = NSImage(size: NSSize(width: s, height: s), flipped: true) { rect in
            NSColor.clear.set()
            rect.fill()
            let bp = combinedBezierPath()
            let sc = min(rect.width / viewWidth, rect.height / viewHeight)
            let padX = (rect.width - viewWidth * sc) / 2
            let padY = (rect.height - viewHeight * sc) / 2
            NSGraphicsContext.current?.saveGraphicsState()
            let tf = NSAffineTransform()
            tf.translateX(by: padX, yBy: padY)
            tf.scaleX(by: sc, yBy: sc)
            tf.translateX(by: -viewMinX, yBy: -viewMinY)
            tf.concat()
            NSColor.white.setFill()
            bp.fill()
            NSGraphicsContext.current?.restoreGraphicsState()
            return true
        }
        img.isTemplate = true
        return img
    }

    private static func combinedBezierPath() -> NSBezierPath {
        let out = NSBezierPath()
        for d in pathDs {
            appendPathData(d, to: out)
        }
        return out
    }

    private static func appendPathData(_ d: String, to path: NSBezierPath) {
        var r = PathReader(d)
        var current = NSPoint.zero
        var subStart = NSPoint.zero
        var cmd: Character = " "

        while !r.isAtEnd {
            r.skipSeparators()
            if r.isAtEnd { break }
            if r.peekIsCommand() {
                cmd = r.consumeCommand()
                if cmd == "Z" || cmd == "z" {
                    path.close()
                    current = subStart
                }
                continue
            }
            switch cmd {
            case "M":
                guard let x = r.readNumber(), let y = r.readNumber() else { return }
                current = NSPoint(x: x, y: y)
                subStart = current
                path.move(to: current)
                cmd = "L"
            case "L":
                guard let x = r.readNumber(), let y = r.readNumber() else { return }
                current = NSPoint(x: x, y: y)
                path.line(to: current)
            case "H":
                guard let x = r.readNumber() else { return }
                current.x = x
                path.line(to: current)
            case "V":
                guard let y = r.readNumber() else { return }
                current.y = y
                path.line(to: current)
            case "C":
                guard let x1 = r.readNumber(), let y1 = r.readNumber(),
                      let x2 = r.readNumber(), let y2 = r.readNumber(),
                      let x = r.readNumber(), let y = r.readNumber()
                else { return }
                let cp1 = NSPoint(x: x1, y: y1)
                let cp2 = NSPoint(x: x2, y: y2)
                let end = NSPoint(x: x, y: y)
                path.curve(to: end, controlPoint1: cp1, controlPoint2: cp2)
                current = end
            default:
                return
            }
        }
    }

    private struct PathReader {
        let s: String
        var i: String.Index
        init(_ s: String) {
            self.s = s
            i = s.startIndex
        }
        var isAtEnd: Bool { i >= s.endIndex }

        mutating func skipSeparators() {
            while i < s.endIndex {
                let ch = s[i]
                if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" || ch == "," {
                    s.formIndex(after: &i)
                } else {
                    break
                }
            }
        }

        func peekIsCommand() -> Bool {
            var j = i
            while j < s.endIndex {
                let ch = s[j]
                if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" || ch == "," {
                    s.formIndex(after: &j)
                } else {
                    break
                }
            }
            guard j < s.endIndex else { return false }
            return "MmLlHhVvCcZz".contains(s[j])
        }

        mutating func consumeCommand() -> Character {
            skipSeparators()
            let ch = s[i]
            s.formIndex(after: &i)
            return ch
        }

        mutating func readNumber() -> CGFloat? {
            skipSeparators()
            guard i < s.endIndex else { return nil }
            let start = i
            var j = i
            if s[j] == "-" || s[j] == "+" {
                s.formIndex(after: &j)
            }
            var sawDigit = false
            var dot = false
            while j < s.endIndex {
                let ch = s[j]
                if ch.isWholeNumber {
                    sawDigit = true
                    s.formIndex(after: &j)
                } else if ch == "." && !dot {
                    dot = true
                    s.formIndex(after: &j)
                } else if (ch == "e" || ch == "E"), sawDigit {
                    s.formIndex(after: &j)
                    if j < s.endIndex, s[j] == "-" || s[j] == "+" {
                        s.formIndex(after: &j)
                    }
                    while j < s.endIndex, s[j].isWholeNumber {
                        s.formIndex(after: &j)
                    }
                    break
                } else {
                    break
                }
            }
            guard sawDigit, j > start else { return nil }
            let slice = String(s[start ..< j])
            guard let v = Double(slice) else { return nil }
            i = j
            return CGFloat(v)
        }
    }
}
