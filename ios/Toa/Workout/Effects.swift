import AVFoundation
import Observation
import SwiftUI
import UserNotifications

/// Short synthesized chimes (same notes as the web app). The audio session mixes
/// with the user's music instead of interrupting it.
@MainActor
final class Sounds {
    static let shared = Sounds()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private lazy var check = render([(587.33, 0, 0.09, 0.25, false), (880.0, 0.06, 0.16, 0.3, false)])
    private lazy var timerDone = render([(523.25, 0, 0.18, 0.3, true), (659.25, 0.14, 0.18, 0.3, true), (783.99, 0.28, 0.35, 0.3, true)])

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func playSetCheck() { play(check) }
    func playTimerDone() { play(timerDone) }

    private func play(_ buffer: AVAudioPCMBuffer?) {
        guard let buffer else { return }
        do {
            if !engine.isRunning { try engine.start() }
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            player.play()
        } catch {
            print("Sound failed: \(error)")
        }
    }

    /// Notes: (frequency, start, duration, peak gain, triangle wave).
    private func render(_ notes: [(Double, Double, Double, Float, Bool)]) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let length = notes.map { $0.1 + $0.2 }.max() ?? 0
        let frames = AVAudioFrameCount(length * sampleRate) + 1
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { samples[i] = 0 }
        for (frequency, start, duration, peak, triangle) in notes {
            let first = Int(start * sampleRate)
            let count = Int(duration * sampleRate)
            let attack = 0.015
            for n in 0..<count where first + n < Int(frames) {
                let t = Double(n) / sampleRate
                let phase = (t * frequency).truncatingRemainder(dividingBy: 1)
                let wave = triangle ? Float(4 * abs(phase - 0.5) - 1) : Float(sin(2 * .pi * phase))
                // Linear attack, then exponential decay down to 0.001 at the end.
                let decay: Double = pow(0.001 / Double(peak), (t - attack) / max(duration - attack, 0.001))
                let gain: Float = t < attack ? peak * Float(t / attack) : peak * Float(decay)
                samples[first + n] += wave * gain
            }
        }
        return buffer
    }
}

/// Rest countdown. Based on an end date so it keeps running in the background,
/// where a local notification replaces the chime.
@MainActor
@Observable
final class RestTimer {
    private(set) var endDate: Date?
    private var task: Task<Void, Never>?
    private static let notificationId = "toa.rest"

    var isRunning: Bool { (endDate?.timeIntervalSinceNow ?? 0) > 0 }

    func start(seconds: Int) {
        guard seconds > 0 else { return stop() }
        endDate = Date().addingTimeInterval(TimeInterval(seconds))
        reschedule()
    }

    func adjust(by delta: Int) {
        guard let endDate, isRunning else {
            if delta > 0 { start(seconds: delta) }
            return
        }
        let remaining = endDate.timeIntervalSinceNow + TimeInterval(delta)
        if remaining <= 0 { stop() } else { start(seconds: Int(remaining.rounded())) }
    }

    func stop() {
        endDate = nil
        task?.cancel()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
    }

    private func reschedule() {
        task?.cancel()
        guard let endDate else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
        let seconds = endDate.timeIntervalSinceNow
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = "Rest is over"
            content.body = "Time for your next set."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: Self.notificationId, content: content, trigger: trigger))
        }
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            // In the foreground the chime plays and the notification isn't shown.
            Sounds.shared.playTimerDone()
            self.endDate = nil
        }
    }
}

/// Short confetti burst, replayed each time `trigger` changes.
struct ConfettiView: View {
    let trigger: Int

    private struct Piece {
        let x: Double, vx: Double, vy: Double, spin: Double, size: Double, color: Color
    }

    @State private var pieces: [Piece] = []
    @State private var start = Date.distantPast
    private let lifetime = 2.6

    var body: some View {
        TimelineView(.animation(paused: pieces.isEmpty)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                guard t < lifetime else { return }
                for piece in pieces {
                    let x = piece.x * size.width + piece.vx * t
                    let y = -20 + piece.vy * t + 420 * t * t
                    let rect = CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2)
                    var copy = context
                    copy.opacity = max(0, 1 - t / lifetime)
                    copy.translateBy(x: x, y: y)
                    copy.rotate(by: .radians(piece.spin * t))
                    copy.fill(Path(rect), with: .color(piece.color))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onChange(of: trigger) {
            let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]
            pieces = (0..<120).map { _ in
                Piece(x: .random(in: 0...1), vx: .random(in: -80...80), vy: .random(in: 0...260),
                      spin: .random(in: -8...8), size: .random(in: 7...12), color: colors.randomElement()!)
            }
            start = Date()
            Task {
                try? await Task.sleep(for: .seconds(lifetime))
                pieces = []
            }
        }
    }
}

/// Autosave of the workout editor (one draft at a time).
enum DraftStore {
    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "workout-draft.json")
    }

    static func save(_ draft: WorkoutDraft) {
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(draft).write(to: url, options: .atomic)
    }

    static func load() -> WorkoutDraft? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WorkoutDraft.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
