import AppKit

/// Provider marks as embedded SVG path data (from homarr-labs/dashboard-icons:
/// anthropic.svg, openai-light.svg), drawn as vectors so they stay crisp at menu-bar
/// size and take the provider's bar colour in light and dark menu bars.
enum ProviderLogo {
    case anthropic, openAI

    private var source: (viewBox: CGFloat, d: String) {
        switch self {
        case .anthropic:
            return (248, "M52.4285 162.873L98.7844 136.879L99.5485 134.602L98.7844 133.334H96.4921L88.7237 132.862L62.2346 132.153L39.3113 131.207L17.0249 130.026L11.4214 128.844L6.2 121.873L6.7094 118.447L11.4214 115.257L18.171 115.847L33.0711 116.911L55.485 118.447L71.6586 119.392L95.728 121.873H99.5485L100.058 120.337L98.7844 119.392L97.7656 118.447L74.5877 102.732L49.4995 86.1905L36.3823 76.62L29.3779 71.7757L25.8121 67.2858L24.2839 57.3608L30.6515 50.2716L39.3113 50.8623L41.4763 51.4531L50.2636 58.1879L68.9842 72.7209L93.4357 90.6804L97.0015 93.6343L98.4374 92.6652L98.6571 91.9801L97.0015 89.2625L83.757 65.2772L69.621 40.8192L63.2534 30.6579L61.5978 24.632C60.9565 22.1032 60.579 20.0111 60.579 17.4246L67.8381 7.49965L71.9133 6.19995L81.7193 7.49965L85.7946 11.0443L91.9074 24.9865L101.714 46.8451L116.996 76.62L121.453 85.4816L123.873 93.6343L124.764 96.1155H126.292V94.6976L127.566 77.9197L129.858 57.3608L132.15 30.8942L132.915 23.4505L136.608 14.4708L143.994 9.62643L149.725 12.344L154.437 19.0788L153.8 23.4505L150.998 41.6463L145.522 70.1215L141.957 89.2625H143.994L146.414 86.7813L156.093 74.0206L172.266 53.698L179.398 45.6635L187.803 36.802L193.152 32.5484H203.34L210.726 43.6549L207.415 55.1159L196.972 68.3492L188.312 79.5739L175.896 96.2095L168.191 109.585L168.882 110.689L170.738 110.53L198.755 104.504L213.91 101.787L231.994 98.7149L240.144 102.496L241.036 106.395L237.852 114.311L218.495 119.037L195.826 123.645L162.07 131.592L161.696 131.893L162.137 132.547L177.36 133.925L183.855 134.279H199.774L229.447 136.524L237.215 141.605L241.8 147.867L241.036 152.711L229.065 158.737L213.019 154.956L175.45 145.977L162.587 142.787H160.805V143.85L171.502 154.366L191.242 172.089L215.82 195.011L217.094 200.682L213.91 205.172L210.599 204.699L188.949 188.394L180.544 181.069L161.696 165.118H160.422V166.772L164.752 173.152L187.803 207.771L188.949 218.405L187.294 221.832L181.308 223.959L174.813 222.777L161.187 203.754L147.305 182.486L136.098 163.345L134.745 164.2L128.075 235.42L125.019 239.082L117.887 241.8L111.902 237.31L108.718 229.984L111.902 215.452L115.722 196.547L118.779 181.541L121.58 162.873L123.291 156.636L123.14 156.219L121.773 156.449L107.699 175.752L86.304 204.699L69.3663 222.777L65.291 224.431L58.2867 220.768L58.9235 214.27L62.8713 208.48L86.304 178.705L100.44 160.155L109.551 149.507L109.462 147.967L108.959 147.924L46.6977 188.512L35.6182 189.93L30.7788 185.44L31.4156 178.115L33.7079 175.752L52.4285 162.873Z")
        case .openAI:
            return (24, "M22.282 9.821a6 6 0 0 0-.516-4.91 6.05 6.05 0 0 0-6.51-2.9A6.065 6.065 0 0 0 4.981 4.18a6 6 0 0 0-3.998 2.9 6.05 6.05 0 0 0 .743 7.097 5.98 5.98 0 0 0 .51 4.911 6.05 6.05 0 0 0 6.515 2.9A6 6 0 0 0 13.26 24a6.06 6.06 0 0 0 5.772-4.206 6 6 0 0 0 3.997-2.9 6.06 6.06 0 0 0-.747-7.073M13.26 22.43a4.48 4.48 0 0 1-2.876-1.04l.141-.081 4.779-2.758a.8.8 0 0 0 .392-.681v-6.737l2.02 1.168a.07.07 0 0 1 .038.052v5.583a4.504 4.504 0 0 1-4.494 4.494M3.6 18.304a4.47 4.47 0 0 1-.535-3.014l.142.085 4.783 2.759a.77.77 0 0 0 .78 0l5.843-3.369v2.332a.08.08 0 0 1-.033.062L9.74 19.95a4.5 4.5 0 0 1-6.14-1.646M2.34 7.896a4.5 4.5 0 0 1 2.366-1.973V11.6a.77.77 0 0 0 .388.677l5.815 3.354-2.02 1.168a.08.08 0 0 1-.071 0l-4.83-2.786A4.504 4.504 0 0 1 2.34 7.872zm16.597 3.855-5.833-3.387L15.119 7.2a.08.08 0 0 1 .071 0l4.83 2.791a4.494 4.494 0 0 1-.676 8.105v-5.678a.79.79 0 0 0-.407-.667m2.01-3.023-.141-.085-4.774-2.782a.78.78 0 0 0-.785 0L9.409 9.23V6.897a.07.07 0 0 1 .028-.061l4.83-2.787a4.5 4.5 0 0 1 6.68 4.66zm-12.64 4.135-2.02-1.164a.08.08 0 0 1-.038-.057V6.075a4.5 4.5 0 0 1 7.375-3.453l-.142.08L8.704 5.46a.8.8 0 0 0-.393.681zm1.097-2.365 2.602-1.5 2.607 1.5v2.999l-2.597 1.5-2.607-1.5Z")
        }
    }

    /// Parsed once; scaled per draw.
    private static let anthropicPath = SVGPath.parse(ProviderLogo.anthropic.source.d)
    private static let openAIPath = SVGPath.parse(ProviderLogo.openAI.source.d)

    func draw(in rect: CGRect, color: NSColor) {
        let path = (self == .anthropic ? Self.anthropicPath : Self.openAIPath).copy() as! NSBezierPath
        let scale = min(rect.width, rect.height) / source.viewBox
        var transform = AffineTransform(translationByX: rect.minX, byY: rect.minY)
        transform.scale(scale)
        path.transform(using: transform)
        color.setFill()
        path.fill()
    }
}

/// Minimal SVG path-data parser: M L H V C A Z (absolute and relative), which is
/// all the embedded logos use. Arcs are converted to cubic Béziers.
enum SVGPath {
    static func parse(_ d: String) -> NSBezierPath {
        var scanner = Scanner(Array(d.utf8))
        let path = NSBezierPath()
        var current = CGPoint.zero, start = CGPoint.zero
        var command: UInt8 = 0

        while scanner.skipSeparators(), !scanner.atEnd {
            if let c = scanner.command() {
                command = c
            } else if command == 0 {
                break
            }
            let relative = command >= UInt8(ascii: "a")
            let base = relative ? current : .zero
            func point() -> CGPoint {
                let x = scanner.number(), y = scanner.number()
                return CGPoint(x: base.x + x, y: base.y + y)
            }
            switch command | 0x20 {  // lowercase
            case UInt8(ascii: "m"):
                current = point(); start = current
                path.move(to: current)
                command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")  // implicit lineto
            case UInt8(ascii: "l"):
                current = point(); path.line(to: current)
            case UInt8(ascii: "h"):
                current.x = base.x + scanner.number(); path.line(to: current)
            case UInt8(ascii: "v"):
                current.y = base.y + scanner.number(); path.line(to: current)
            case UInt8(ascii: "c"):
                let c1 = point(), c2 = point(), end = point()
                path.curve(to: end, controlPoint1: c1, controlPoint2: c2)
                current = end
            case UInt8(ascii: "a"):
                let rx = scanner.number(), ry = scanner.number(), angle = scanner.number()
                let large = scanner.flag(), sweep = scanner.flag()
                let end = point()
                appendArc(to: path, from: current, to: end, rx: rx, ry: ry,
                          angle: angle, large: large, sweep: sweep)
                current = end
            case UInt8(ascii: "z"):
                path.close(); current = start
            default:
                assertionFailure("Unsupported SVG path command \(UnicodeScalar(command))")
                return path
            }
        }
        return path
    }

    /// SVG endpoint arc → centre parameterisation → ≤90° cubic segments (SVG 1.1 F.6).
    private static func appendArc(to path: NSBezierPath, from p1: CGPoint, to p2: CGPoint,
                                  rx: CGFloat, ry: CGFloat, angle: CGFloat,
                                  large: Bool, sweep: Bool) {
        var rx = abs(rx), ry = abs(ry)
        guard rx > 0, ry > 0, p1 != p2 else { path.line(to: p2); return }
        let phi = angle * .pi / 180, cosP = cos(phi), sinP = sin(phi)
        let dx = (p1.x - p2.x) / 2, dy = (p1.y - p2.y) / 2
        let x1 = cosP * dx + sinP * dy, y1 = -sinP * dx + cosP * dy
        let lambda = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
        if lambda > 1 { rx *= lambda.squareRoot(); ry *= lambda.squareRoot() }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let coef = (max(0, num / den)).squareRoot() * (large == sweep ? -1 : 1)
        let cxp = coef * rx * y1 / ry, cyp = -coef * ry * x1 / rx
        let cx = cosP * cxp - sinP * cyp + (p1.x + p2.x) / 2
        let cy = sinP * cxp + cosP * cyp + (p1.y + p2.y) / 2

        func vectorAngle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let ux = (x1 - cxp) / rx, uy = (y1 - cyp) / ry
        let vx = (-x1 - cxp) / rx, vy = (-y1 - cyp) / ry
        var theta = vectorAngle(1, 0, ux, uy)
        var delta = vectorAngle(ux, uy, vx, vy)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        func pointAt(_ t: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(t) * cosP - ry * sin(t) * sinP,
                    y: cy + rx * cos(t) * sinP + ry * sin(t) * cosP)
        }
        func derivative(_ t: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(t) * cosP - ry * cos(t) * sinP,
                    y: -rx * sin(t) * sinP + ry * cos(t) * cosP)
        }
        let segments = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
        let step = delta / CGFloat(segments)
        let k = 4 / 3 * tan(step / 4)
        for _ in 0..<segments {
            let a = pointAt(theta), da = derivative(theta)
            let b = pointAt(theta + step), db = derivative(theta + step)
            path.curve(to: b,
                       controlPoint1: CGPoint(x: a.x + k * da.x, y: a.y + k * da.y),
                       controlPoint2: CGPoint(x: b.x - k * db.x, y: b.y - k * db.y))
            theta += step
        }
    }

    private struct Scanner {
        let bytes: [UInt8]
        var i = 0
        init(_ bytes: [UInt8]) { self.bytes = bytes }

        var atEnd: Bool { i >= bytes.count }

        @discardableResult
        mutating func skipSeparators() -> Bool {
            while i < bytes.count, bytes[i] == 0x20 || bytes[i] == 0x2C || bytes[i] == 0x0A
                    || bytes[i] == 0x09 || bytes[i] == 0x0D { i += 1 }
            return true
        }

        mutating func command() -> UInt8? {
            guard i < bytes.count else { return nil }
            let b = bytes[i] | 0x20
            guard b >= UInt8(ascii: "a"), b <= UInt8(ascii: "z"), b != UInt8(ascii: "e") else { return nil }
            i += 1
            return bytes[i - 1]
        }

        mutating func flag() -> Bool {
            skipSeparators()
            defer { i += 1 }
            return i < bytes.count && bytes[i] == UInt8(ascii: "1")
        }

        /// Reads one number; handles compact forms like `.8.8` and `-.516-4.91`.
        mutating func number() -> CGFloat {
            skipSeparators()
            let begin = i
            if i < bytes.count, bytes[i] == UInt8(ascii: "-") || bytes[i] == UInt8(ascii: "+") { i += 1 }
            var seenDot = false
            while i < bytes.count {
                let b = bytes[i]
                if b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9") { i += 1 }
                else if b == UInt8(ascii: "."), !seenDot { seenDot = true; i += 1 }
                else if b | 0x20 == UInt8(ascii: "e") {
                    i += 1
                    if i < bytes.count, bytes[i] == UInt8(ascii: "-") || bytes[i] == UInt8(ascii: "+") { i += 1 }
                }
                else { break }
            }
            return CGFloat(Double(String(decoding: bytes[begin..<i], as: UTF8.self)) ?? 0)
        }
    }
}
