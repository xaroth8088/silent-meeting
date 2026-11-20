import AVFoundation
import CoreMedia
import Foundation

final class CapturePipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let videoQueue = DispatchQueue(label: "Silent Meeting film rendering", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "Silent Meeting microphone capture", qos: .userInitiated)
    private let audio = AVCaptureAudioDataOutput()
    private let video = AVCaptureVideoDataOutput()
    private let renderer = FilmRenderer()
    private let sink: CameraSink
    private var speech: SpeechPipeline?
    private var dialogue = DialogueCards()
    private var lastThumbnail = DispatchTime(uptimeNanoseconds: 0)
    private var active = false
    private let preview: (CGImage, Bool) -> Void

    init(target: CameraSink.Target = .silentMeeting, preview: @escaping (CGImage, Bool) -> Void) {
        self.sink = CameraSink(target: target)
        self.preview = preview
        super.init()
    }

    // The caller serializes the lifecycle on a capture-configuration queue.
    func start(camera: AVCaptureDevice, microphone: AVCaptureDevice) throws {
        guard let model = Bundle.main.url(forResource: "ggml-tiny-q5_1", withExtension: "bin"),
              let speech = SpeechPipeline(model: model, publish: { [weak self] text in
                  guard let self else { return }
                  self.videoQueue.async { if self.active { self.dialogue.enqueue(text) } }
              })
        else { throw CaptureError.model }
        self.speech = speech
        let cameraInput = try AVCaptureDeviceInput(device: camera)
        let microphoneInput = try AVCaptureDeviceInput(device: microphone)
        session.beginConfiguration()
        do {
            if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
            guard session.canAddInput(cameraInput) else { throw CaptureError.camera }
            session.addInput(cameraInput)
            guard session.canAddInput(microphoneInput) else { throw CaptureError.microphone }
            session.addInput(microphoneInput)

            video.alwaysDiscardsLateVideoFrames = true
            video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            video.setSampleBufferDelegate(self, queue: videoQueue)
            guard session.canAddOutput(video) else { throw CaptureError.camera }
            session.addOutput(video)

            audio.audioSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: VoiceEndpointer.rate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
            audio.setSampleBufferDelegate(self, queue: audioQueue)
            guard session.canAddOutput(audio) else { throw CaptureError.microphone }
            session.addOutput(audio)
        } catch {
            session.commitConfiguration()
            throw error
        }
        session.commitConfiguration()
        videoQueue.sync { active = true }
        session.startRunning()
        guard session.isRunning else {
            stop()
            throw CaptureError.start
        }
    }

    func stop() {
        session.stopRunning()
        videoQueue.sync {
            active = false
            sink.stop()
            dialogue = DialogueCards()
        }
        audioQueue.sync { speech = nil }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if output === audio {
            speech?.append(sampleBuffer)
            return
        }
        guard active, let pixels = sampleBuffer.imageBuffer else { return }
        let now = DispatchTime.now()
        guard let frame = renderer.render(pixels, title: dialogue.text(at: now)) else { return }

        let connected = sink.send(frame)
        if now >= lastThumbnail + .milliseconds(125), let thumbnail = renderer.thumbnail(frame) {
            lastThumbnail = now
            preview(thumbnail, connected)
        }
    }
}

private enum CaptureError: LocalizedError {
    case model, camera, microphone, start

    var errorDescription: String? {
        switch self {
        case .model: return "The bundled speech model could not be opened. Reinstall Silent Meeting."
        case .camera: return "Couldn't start the selected camera."
        case .microphone: return "Couldn't start the selected microphone."
        case .start: return "Capture couldn't start. Check whether another app is using the selected devices."
        }
    }
}
