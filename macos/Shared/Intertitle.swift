import CoreGraphics
import CoreText
import CoreVideo
import Foundation

enum Intertitle {
    static func draw(_ text: String, into frame: CVPixelBuffer, standby: Bool = false) {
        CVPixelBufferLockBaseAddress(frame, [])
        defer { CVPixelBufferUnlockBaseAddress(frame, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(frame),
                                  width: CameraFormat.width, height: CameraFormat.height,
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(frame),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue |
                                              CGImageAlphaInfo.premultipliedFirst.rawValue) else { return }

        let canvas = CGRect(x: 0, y: 0, width: CameraFormat.width, height: CameraFormat.height)
        ctx.setFillColor(gray: 0.028, alpha: 1)
        ctx.fill(canvas)
        let dark = CGColor(gray: 0.017, alpha: 1)
        let light = CGColor(gray: 0.049, alpha: 1)
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [light, dark] as CFArray,
                                     locations: [0, 1]) {
            let center = CGPoint(x: canvas.midX, y: canvas.midY)
            ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                   endRadius: 740, options: .drawsAfterEndLocation)
        }
        let first = canvas.insetBy(dx: 72, dy: 67)
        let second = first.insetBy(dx: 15, dy: 13)
        ctx.setStrokeColor(gray: 0.62, alpha: 1)
        ctx.setLineWidth(3)
        ctx.stroke(first)
        ctx.setStrokeColor(gray: 0.36, alpha: 1)
        ctx.setLineWidth(1)
        ctx.stroke(second)
        ctx.setFillColor(gray: 0.72, alpha: 1)
        for x in [second.minX, second.maxX] {
            for y in [second.minY, second.maxY] {
                diamond(in: ctx, x: x, y: y, radius: 9)
            }
        }
        for y in [143.0, canvas.height - 143] {
            ctx.fill(CGRect(x: canvas.midX - 118, y: y - 0.5, width: 236, height: 1))
            diamond(in: ctx, x: canvas.midX, y: y, radius: 7)
        }
        drawText(text, in: ctx, canvas: canvas, fontSize: standby ? 43 : 57)
    }

    private static func diamond(in ctx: CGContext, x: CGFloat, y: CGFloat, radius: CGFloat) {
        ctx.move(to: CGPoint(x: x, y: y + radius))
        ctx.addLine(to: CGPoint(x: x + radius, y: y))
        ctx.addLine(to: CGPoint(x: x, y: y - radius))
        ctx.addLine(to: CGPoint(x: x - radius, y: y))
        ctx.closePath()
        ctx.fillPath()
    }

    private static func drawText(_ text: String, in ctx: CGContext, canvas: CGRect, fontSize: CGFloat) {
        let width = canvas.width * 0.70
        let font = CTFontCreateWithName("Georgia" as CFString, fontSize, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.91, alpha: 1),
        ])
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var lines: [CTLine] = []
        var offset = 0
        while offset < attributed.length {
            let count = max(1, CTTypesetterSuggestLineBreak(typesetter, offset, width))
            lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: count)))
            offset += count
        }
        guard !lines.isEmpty else { return }
        let lineHeight = fontSize * 1.34
        let scale = min(1, 354 / (CGFloat(lines.count) * lineHeight))
        ctx.translateBy(x: canvas.midX, y: canvas.midY)
        ctx.scaleBy(x: scale, y: scale)
        for (index, line) in lines.enumerated() {
            let x = CTLineGetPenOffsetForFlush(line, 0.5, 0)
            let y = (CGFloat(lines.count - 1) / 2 - CGFloat(index)) * lineHeight - fontSize * 0.29
            ctx.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(line, ctx)
        }
    }
}
