import AVFoundation
import Speech

/// On-device speech recognition — the native upgrade over Safari's Web Speech.
final class SpeechManager: NSObject, ObservableObject {
    @Published var transcript = ""
    @Published var listening = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    var onFinal: ((String) -> Void)?

    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
    }

    func start() {
        guard !listening else { return }
        transcript = ""
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement,
                                 options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true {
            req.requiresOnDeviceRecognition = true
        }
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buf, _ in
            req.append(buf)
        }
        engine.prepare()
        try? engine.start()
        listening = true

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let r = result {
                DispatchQueue.main.async { self.transcript = r.bestTranscription.formattedString }
                self.bumpSilenceTimer()
                if r.isFinal { self.finish() }
            }
            if error != nil { self.finish() }
        }
        bumpSilenceTimer(seconds: 6)          // give the first words time to arrive
    }

    private func bumpSilenceTimer(seconds: TimeInterval = 1.6) {
        DispatchQueue.main.async {
            self.silenceTimer?.invalidate()
            self.silenceTimer = Timer.scheduledTimer(withTimeInterval: seconds,
                                                     repeats: false) { _ in
                self.finish()
            }
        }
    }

    func finish() {
        guard listening else { return }
        listening = false
        silenceTimer?.invalidate()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { onFinal?(text) }
    }
}

/// Plays the base64 WAV replies from Piper.
final class WavPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var speaking = false
    private var player: AVAudioPlayer?
    var onDone: (() -> Void)?

    func play(base64: String) {
        guard let data = Data(base64Encoded: base64), !data.isEmpty else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [])   // ignores the ring/silent switch
        try? session.setActive(true)
        player = try? AVAudioPlayer(data: data)
        player?.delegate = self
        speaking = player?.play() ?? false
    }

    func stop() {
        player?.stop()
        speaking = false
    }

    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully f: Bool) {
        speaking = false
        onDone?()
    }
}
