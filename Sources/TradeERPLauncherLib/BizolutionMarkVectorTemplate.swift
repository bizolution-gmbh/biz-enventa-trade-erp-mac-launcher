import AppKit

/// Menüleisten-Template aus derselben Geometrie wie `bizolution-mark-farbe-rgb.svg` (Rechteck + zwei Pfade), weiß auf transparent, `NSImage.isTemplate = true`.
enum BizolutionMarkVectorTemplate {
    private static let viewMinX: CGFloat = 0
    /// Ober-/Unterrand des ursprünglichen 771.61×915.99-Motivs abgeschnitten → quadratisches Mark-`viewBox` wie `bizolution-mark-farbe-rgb.svg`.
    private static let squareCropMinY: CGFloat = (915.99 - 771.61) / 2
    private static let viewMinY: CGFloat = squareCropMinY
    private static let viewWidth: CGFloat = 771.61
    private static let viewHeight: CGFloat = 771.61
    private static let markSquareViewRect = NSRect(x: 0, y: squareCropMinY, width: viewWidth, height: viewHeight)

    /// Play-Dreieck in Marke-SVG-Koordinaten (`app-icon-play.svg`).
    private static let playA = CGPoint(x: 380.9824, y: 457.9950)
    private static let playB = CGPoint(x: 380.9824, y: 843.8)
    private static let playC = CGPoint(x: 771.61, y: 650.8975)

    private static let pathDs: [String] = [
        "M349.63,307.83h-101.42v-112.79c0-3.31-2.69-6-6-6h-54.47c-3.31,0-6,2.69-6,6v280.68c0,68.71,41.49,127.91,100.72,153.87l63.38-52.53c-54.18-1.99-97.63-46.69-97.63-101.34v-101.42h101.42c23.71,0,45.54,8.17,62.84,21.86h84.98c-28.4-52.55-84-88.33-147.81-88.33Z",
        "M584.45,515.19l-184.07,152.59h183.49c3.31,0,6,2.69,6,6v54.47c0,3.31-2.69,6-6,6h-268.92c-3.81,0-6.9-3.09-6.9-6.9v-62.59c0-4.47,1.99-8.7,5.43-11.55l184.07-152.59h-183.49c-3.31,0-6-2.69-6-6v-54.47c0-3.31,2.69-6,6-6h268.92c3.81,0,6.9,3.09,6.9,6.9v62.59c0,4.47-1.99,8.7-5.43,11.55Z",
    ]

    static func menuBarTemplateImage(side: CGFloat = 18) -> NSImage {
        let s = max(16, side)
        let img = NSImage(size: NSSize(width: s, height: s), flipped: true) { rect in
            NSColor.clear.set()
            rect.fill()
            let bp = buildCombinedMarkPath()
            let fit = Self.trayCompositeBounds
            let sc = min(rect.width / fit.width, rect.height / fit.height)
            let padX = (rect.width - fit.width * sc) / 2
            let padY = (rect.height - fit.height * sc) / 2
            NSGraphicsContext.current?.saveGraphicsState()
            let tf = NSAffineTransform()
            tf.translateX(by: padX, yBy: padY)
            tf.scaleX(by: sc, yBy: sc)
            tf.translateX(by: -fit.minX, yBy: -fit.minY)
            tf.concat()
            NSColor.white.setFill()
            bp.fill()
            // Play in SVG-Nutzerkoordinaten (wie `app-icon-play.svg`), gleiche Transformation wie die Marke.
            drawMenuBarPlayTriangleInMarkSpace()
            NSGraphicsContext.current?.restoreGraphicsState()
            return true
        }
        img.isTemplate = true
        return img
    }

    /// Play-Dreieck in Marke-SVG-Koordinaten (wie `app-icon-play.svg`: ~1,5× breiter, volle BR-Höhe, Schwerpunkt leicht links der Quadrantenmitte).
    private static func drawMenuBarPlayTriangleInMarkSpace() {
        guard let gc = NSGraphicsContext.current else { return }
        let a = Self.playA
        let b = Self.playB
        let c = Self.playC
        let outer = Self.scaledTriangleCorners(a: a, b: b, c: c, factor: 1.11)
        let inner = Self.scaledTriangleCorners(a: a, b: b, c: c, factor: 0.94)
        let pathOuter = trianglePath(a: outer.0, b: outer.1, c: outer.2)
        let pathInner = trianglePath(a: inner.0, b: inner.1, c: inner.2)
        gc.saveGraphicsState()
        gc.compositingOperation = .clear
        pathOuter.fill()
        gc.compositingOperation = .sourceOver
        NSColor.white.withAlphaComponent(0.8).setFill()
        pathInner.fill()
        gc.restoreGraphicsState()
    }

    private static func scaledTriangleCorners(a: CGPoint, b: CGPoint, c: CGPoint, factor: CGFloat) -> (CGPoint, CGPoint, CGPoint) {
        let gx = (a.x + b.x + c.x) / 3
        let gy = (a.y + b.y + c.y) / 3
        func t(_ p: CGPoint) -> CGPoint {
            CGPoint(x: gx + (p.x - gx) * factor, y: gy + (p.y - gy) * factor)
        }
        return (t(a), t(b), t(c))
    }

    private static func trianglePath(a: CGPoint, b: CGPoint, c: CGPoint) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: a)
        p.line(to: b)
        p.line(to: c)
        p.close()
        p.lineJoinStyle = .round
        p.lineCapStyle = .round
        return p
    }

    /// Bounding Box der Marke im quadratischen Zuschnitt (wie `viewBox` der SVG-Datei).
    private static let inkBounds: NSRect = {
        let b = buildCombinedMarkPath().bounds
        if b.width < 1 || b.height < 1 {
            return markSquareViewRect
        }
        let o = max(b.width, b.height) * 0.02
        let expanded = NSRect(x: b.minX - o, y: b.minY - o, width: b.width + 2 * o, height: b.height + 2 * o)
        let clipped = expanded.intersection(markSquareViewRect)
        if clipped.width > 2, clipped.height > 2 {
            return clipped
        }
        return markSquareViewRect
    }()

    /// Vereinigung aus Mark-`inkBounds` und Play-Dreieck inkl. äußerem Clear-Halo (`factor` 1.11), im quadratischen `viewBox` beschnitten — verhindert Abschneiden im Tray.
    private static let trayCompositeBounds: NSRect = {
        let outer = scaledTriangleCorners(a: playA, b: playB, c: playC, factor: 1.11)
        let xs = [playA.x, playB.x, playC.x, outer.0.x, outer.1.x, outer.2.x]
        let ys = [playA.y, playB.y, playC.y, outer.0.y, outer.1.y, outer.2.y]
        let xmin = xs.min()!
        let xmax = xs.max()!
        let ymin = ys.min()!
        let ymax = ys.max()!
        let playBox = NSRect(x: xmin, y: ymin, width: max(0, xmax - xmin), height: max(0, ymax - ymin))
        let u = inkBounds.union(playBox).intersection(markSquareViewRect)
        if u.width > 2, u.height > 2 {
            return u
        }
        return markSquareViewRect
    }()

    private static func buildCombinedMarkPath() -> NSBezierPath {
        let out = NSBezierPath()
        let rr = NSRect(x: 430.97, y: 189.04, width: 66.47, height: 66.47)
        out.append(NSBezierPath(roundedRect: rr, xRadius: 6, yRadius: 6))
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
            let op = String(cmd).uppercased().first ?? " "
            let relative = cmd.isLowercase
            switch op {
            case "M":
                let mRel = (cmd == "m")
                guard let x0 = r.readNumber(), let y0 = r.readNumber() else { return }
                var x = x0, y = y0
                if mRel { x += current.x; y += current.y }
                current = NSPoint(x: x, y: y)
                subStart = current
                path.move(to: current)
                let lineRel = mRel
                while !r.isAtEnd, !r.peekIsCommand() {
                    guard let nx = r.readNumber(), let ny = r.readNumber() else { return }
                    var lx = nx, ly = ny
                    if lineRel { lx += current.x; ly += current.y }
                    current = NSPoint(x: lx, y: ly)
                    path.line(to: current)
                }
            case "L":
                guard let x0 = r.readNumber(), let y0 = r.readNumber() else { return }
                var x = x0, y = y0
                if relative { x += current.x; y += current.y }
                current = NSPoint(x: x, y: y)
                path.line(to: current)
            case "H":
                guard let x0 = r.readNumber() else { return }
                var x = x0
                if relative { x += current.x }
                current = NSPoint(x: x, y: current.y)
                path.line(to: current)
            case "V":
                guard let y0 = r.readNumber() else { return }
                var y = y0
                if relative { y += current.y }
                current = NSPoint(x: current.x, y: y)
                path.line(to: current)
            case "C":
                guard let x1 = r.readNumber(), let y1 = r.readNumber(),
                      let x2 = r.readNumber(), let y2 = r.readNumber(),
                      let x = r.readNumber(), let y = r.readNumber()
                else { return }
                var cx1 = x1, cy1 = y1, cx2 = x2, cy2 = y2, ex = x, ey = y
                if relative {
                    cx1 += current.x; cy1 += current.y
                    cx2 += current.x; cy2 += current.y
                    ex += current.x; ey += current.y
                }
                let cp1 = NSPoint(x: cx1, y: cy1)
                let cp2 = NSPoint(x: cx2, y: cy2)
                let end = NSPoint(x: ex, y: ey)
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
