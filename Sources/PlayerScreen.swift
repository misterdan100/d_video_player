import SwiftUI
import AVFoundation
import UIKit

/// Pantalla de reproducción.
/// - Un toque = play/pause (con ícono de confirmación que se desvanece).
/// - Mantener presionado (0.3 s) + arrastrar horizontal = scrub con seek en vivo.
/// - La pantalla no se apaga mientras esta vista está activa.
/// Los gestos viven en VideoLayerView (UIKit); los controles (X, tiempo)
/// respetan el safe area para no quedar debajo del Dynamic Island.
struct PlayerScreen: View {
    let video: VideoSelection
    let onClose: () -> Void

    @State private var player: AVPlayer
    @State private var isPlaying = false
    @State private var feedbackSymbol: String?
    @State private var currentTimeText = "0:00"
    @State private var durationText = "--:--"
    @State private var timeObserver: Any?

    // MARK: Estado del scrub
    @State private var isScrubbing = false
    @State private var wasPlayingBeforeScrub = false
    @State private var scrubStartSeconds: Double = 0
    @State private var scrubTargetSeconds: Double = 0
    @State private var isSeekInFlight = false
    @State private var pendingSeekSeconds: Double?

    /// Sensibilidad fija: arrastrar todo el ancho de la pantalla ≈ 90 segundos.
    private let secondsPerFullWidth: Double = 90

    init(video: VideoSelection, onClose: @escaping () -> Void) {
        self.video = video
        self.onClose = onClose
        _player = State(initialValue: AVPlayer(url: video.url))
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            // El video (y sus gestos) ocupa toda la pantalla.
            VideoLayerView(
                player: player,
                onTap: { togglePlayPause() },
                onScrubBegan: { beginScrub() },
                onScrubMoved: { fraction in updateScrub(widthFraction: fraction) },
                onScrubEnded: { endScrub() }
            )
            .ignoresSafeArea()

            // Ícono grande de confirmación al tocar (play/pause/replay).
            if let feedbackSymbol {
                Image(systemName: feedbackSymbol)
                    .font(.system(size: 72))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(radius: 8)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            // Indicador de scrub: tiempo destino + diferencia.
            if isScrubbing {
                scrubIndicator
                    .allowsHitTesting(false)
            }

            // Controles: DENTRO del safe area (la X ya no queda bajo el Dynamic Island).
            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.4), in: Circle())
                            .contentShape(Circle())
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
                    .allowsHitTesting(false)
            }
            .padding()
        }
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

    // MARK: - Vistas auxiliares

    private var scrubIndicator: some View {
        VStack(spacing: 6) {
            Text(Self.format(scrubTargetSeconds))
                .font(.system(size: 44, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
            Text(deltaText)
                .font(.title3.monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
    }

    private var deltaText: String {
        let delta = scrubTargetSeconds - scrubStartSeconds
        let sign = delta >= 0 ? "+" : "−"
        return "\(sign)\(Self.format(abs(delta)))"
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
            guard !isScrubbing else { return }
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
        guard !isScrubbing else { return }
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

    // MARK: - Scrub (requisito 3)

    private func beginScrub() {
        isScrubbing = true
        wasPlayingBeforeScrub = isPlaying
        player.pause()
        isPlaying = false
        scrubStartSeconds = max(0, player.currentTime().seconds)
        scrubTargetSeconds = scrubStartSeconds
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func updateScrub(widthFraction: Double) {
        guard isScrubbing else { return }
        var target = scrubStartSeconds + widthFraction * secondsPerFullWidth

        // Limitar entre 0 y la duración (si se conoce).
        target = max(0, target)
        if let duration = player.currentItem?.duration, duration.isNumeric {
            target = min(target, max(0, duration.seconds - 0.1))
        }

        scrubTargetSeconds = target
        currentTimeText = Self.format(target)
        requestSeek(to: target)
    }

    private func endScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        requestSeek(to: scrubTargetSeconds)
        if wasPlayingBeforeScrub {
            player.play()
            isPlaying = true
        }
    }

    /// Seek "en vivo" sin saturar: si hay un seek en curso, se guarda el último
    /// tiempo pedido y se ejecuta al terminar el anterior.
    private func requestSeek(to seconds: Double) {
        pendingSeekSeconds = seconds
        guard !isSeekInFlight else { return }
        performNextSeek()
    }

    private func performNextSeek() {
        guard let seconds = pendingSeekSeconds else { return }
        pendingSeekSeconds = nil
        isSeekInFlight = true
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            DispatchQueue.main.async {
                isSeekInFlight = false
                if pendingSeekSeconds != nil {
                    performNextSeek()
                }
            }
        }
    }

    private func playbackEnded() {
        guard !isScrubbing else { return }
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
