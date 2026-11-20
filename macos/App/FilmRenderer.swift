import CoreImage
import CoreMedia
import Foundation

final class FilmRenderer {
    private let canvas = CGRect(x: 0, y: 0, width: CameraFormat.width, height: CameraFormat.height)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorspace = CGColorSpaceCreateDeviceRGB()
    private let pool = CameraFormat.makePool()
    private let noise = CIFilter(name: "CIRandomGenerator")?.outputImage
    private var card: (text: String, image: CIImage)?
    private var frame = 0

    func render(_ source: CVPixelBuffer, title: String?) -> CVPixelBuffer? {
        let input: CIImage
        if let title {
            if let card, card.text == title {
                input = card.image
            } else {
                guard let buffer = CameraFormat.allocate(from: pool) else { return nil }
                Intertitle.draw(title, into: buffer)
                input = CIImage(cvPixelBuffer: buffer)
                card = (title, input)
            }
        } else {
            card = nil
            input = CIImage(cvPixelBuffer: source)
        }

        guard let output = CameraFormat.allocate(from: pool) else { return nil }
        frame = (frame + 1) % 36_000
        let phase = Double(frame)
        let scale = max(canvas.width / input.extent.width, canvas.height / input.extent.height) * 1.018
        let translate = CGAffineTransform(translationX: (canvas.width - input.extent.width * scale) / 2 + 3 * sin(phase * 2.1),
                                          y: (canvas.height - input.extent.height * scale) / 2 + 2.4 * sin(phase * 1.31))
        var film = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale).concatenating(translate))
            .cropped(to: canvas)
            .applyingFilter("CIColorControls", parameters: ["inputSaturation": 0.0,
                                                           "inputContrast": title == nil ? 1.31 : 1.0])
            .applyingFilter("CIExposureAdjust", parameters: ["inputEV": 0.065 * sin(phase * 1.77)])
            .applyingFilter("CIVignette", parameters: ["inputIntensity": 1.15, "inputRadius": 1.6])

        if let noise {
            let value = CIVector(x: 0.333, y: 0.333, z: 0.334, w: 0)
            let grain = noise.transformed(by: CGAffineTransform(translationX: phase * 19, y: phase * 41))
                .cropped(to: canvas)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": value, "inputGVector": value, "inputBVector": value,
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0.16),
                ])
            film = grain.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: film])
        }
        if frame % 19 < 5 {
            let x = Double((frame / 19 * 233 + 57) % (CameraFormat.width - 4))
            let scratch = CIImage(color: CIColor(red: 0.91, green: 0.91, blue: 0.91, alpha: 0.26))
                .cropped(to: CGRect(x: x, y: 64, width: 1.2, height: canvas.height - 140))
            film = scratch.composited(over: film)
        }
        context.render(film, to: output, bounds: canvas, colorSpace: colorspace)
        return output
    }

    func thumbnail(_ frame: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: frame).transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        return context.createCGImage(image, from: image.extent)
    }
}
