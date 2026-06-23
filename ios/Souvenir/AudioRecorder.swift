import Foundation
import AVFoundation

/// Records a voice note to a temporary AAC/m4a file. The captured audio never
/// leaves the device in cleartext — it is read back and encrypted by the store
/// (SECURITY.md §1.4: voice is content). On-device only; no transcription
/// (DESIGN_INTEGRATION.md §5).
@MainActor
final class AudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var finishedURL: URL?
    @Published var permissionDenied = false

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    var durationLabel: String {
        let total = Int(elapsed.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    func toggle() { isRecording ? stop() : start() }

    func start() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else { self.permissionDenied = true; return }
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.record()
            recorder = rec
            finishedURL = nil
            elapsed = 0
            isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in guard let self, let r = self.recorder else { return }; self.elapsed = r.currentTime }
            }
        } catch {
            isRecording = false
        }
    }

    func stop() {
        recorder?.stop()
        timer?.invalidate(); timer = nil
        finishedURL = recorder?.url
        isRecording = false
    }

    func recordedData() -> Data? {
        guard let url = finishedURL else { return nil }
        return try? Data(contentsOf: url)
    }
}
