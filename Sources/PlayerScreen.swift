import SwiftUI
import AVFoundation
import UIKit

/// Pantalla de reproducción.
/// - Un toque = play/pause (con ícono de confirmación que se desvanece).
/// - La pantalla no se apaga mientras esta vista está activa.
/// - El scrub (mantener + arrastrar) llega en la Sesión 2.
struct PlayerScreen: View {
    let video: VideoSelection
    let onClose: () -> Void

    @State private var player: AVPlayer
    @State private var isPlaying = false
    @State private var feedbackSymbol: String?
    @State private var currentTimeText = "0:00"
    @State private var durationText = "--:--"
    @State private var timeObserver: Any?

    init(video: VideoSelection, onClose: @escaping () -> Void) {
        self.video = video
        self.onClose = onClose
        _player = State(initialValue: AVPlayer(url: video.url))
    }

    var body: some View {
        ZStack {
            Color.black
            VideoLayerView(player: player)

            // Ícono grande de confirmación al tocar (play/pause/replay).
            if let feedbackSymbol {
                Image(systemName: feedbackSymbol)
                    .font(.system(size: 72))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(radius: 8)
                    .transition(.opacity)
            }

            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    Spacer()
                }
                Spacer()
                Text("\(currentTimeText) / \(durationText)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.4), in: Capsule())
            }
            .padding()
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { togglePlayPause() }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { start() }
        .onDisappear { cleanup() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSNotification.Name.AVPlayerItemDidPlayToEndTime
        )) { note in
            guard (note.object as? AVPlayerItem) === player.currentItem else { return }
            playbackEnded()
        }
    }

    // MARK: - Ciclo de vida

    private func start() {
        // Requisito 1: la pantalla no se apaga mientras se reproduce.
        UIApplication.shared.isIdleTimerDisabled = true

        // Que suene aunque el iPhone esté en silencio.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { time in
            currentTimeText = Self.format(time.seconds)
            if let duration = player.currentItem?.duration, duration.isNumeric {
                durationText = Self.format(duration.seconds)
            }
        }

        player.play()
        isPlaying = true
    }

    private func cleanup() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player.pause()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Interacción

    /// Requisito 2: un toque en la pantalla = play/pause.
    private func togglePlayPause() {
        if isPlaying {
            player.pause()
            isPlaying = false
            showFeedback("pause.fill")
        } else {
            player.play()
            isPlaying = true
            showFeedback("play.fill")
        }
    }

    private func playbackEnded() {
        isPlaying = false
        player.seek(to: .zero)
        showFeedback("arrow.counterclockwise")
    }

    private func showFeedback(_ symbol: String) {
        withAnimation(.easeIn(duration: 0.1)) { feedbackSymbol = symbol }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.3)) {
                if feedbackSymbol == symbol { feedbackSymbol = nil }
            }
        }
    }

    private static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
