import SwiftUI
import AVFoundation
import UIKit

/// Pantalla de reproducción.
/// - Un toque = play/pause (con ícono de confirmación que se desvanece).
/// - Mantener presionado (0.3 s) + arrastrar horizontal = scrub con seek en vivo.
/// - Panel de controles (X, tiempo, velocidad) reposicionable: arriba, abajo,
///   izquierda o derecha (para videos con contenido abajo, p. ej. piano).
/// - Estilo Liquid Glass en iOS 26+ con fallback a fondo oscuro.
/// - La pantalla no se apaga mientras esta vista está activa.
/// Los gestos viven en VideoLayerView (UIKit); los controles respetan el safe area.
struct PlayerScreen: View {
    let video: VideoSelection
    let onClose: () -> Void

    @State private var player: AVPlayer
    @State private var isPlaying = false
    @State private var feedbackSymbol: String?
    @State private var currentTimeText = "0:00"
    @State private var durationText = "--:--"
    @State private var timeObserver: Any?

    // MARK: Preferencias persistentes
    /// Velocidad de reproducción (0.5–2.0), recordada entre sesiones.
    @AppStorage("playbackSpeed") private var playbackSpeed: Double = 1.0
    /// Posición del panel de controles, recordada entre sesiones.
    @AppStorage("panelPosition") private var panelPositionRaw: String = PanelPosition.top.rawValue

    // MARK: Estado del scrub
    @State private var isScrubbing = false
    @State private var wasPlayingBeforeScrub = false
    @State private var scrubStartSeconds: Double = 0
    @State private var scrubTargetSeconds: Double = 0
    @State private var isSeekInFlight = false
    @State private var pendingSeekSeconds: Double?

    /// Sensibilidad fija: arrastrar todo el ancho de la pantalla ≈ 90 segundos.
    private let secondsPerFullWidth: Double = 90

    /// Velocidades disponibles en el menú.
    private let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    init(video: VideoSelection, onClose: @escaping () -> Void) {
        self.video = video
        self.onClose = onClose
        _player = State(initialValue: AVPlayer(url: video.url))
    }

    private var panelPosition: PanelPosition {
        PanelPosition(rawValue: panelPositionRaw) ?? .top
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

            // Panel de controles, dentro del safe area, en el borde elegido.
            controlPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: panelPosition.alignment)
                .padding(12)
                .opacity(isScrubbing ? 0.25 : 1)
                .animation(.easeInOut(duration: 0.2), value: isScrubbing)
                .animation(.snappy, value: panelPositionRaw)
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

    // MARK: - Panel de controles

    private var controlPanel: some View {
        let layout = panelPosition.isVertical
            ? AnyLayout(VStackLayout(spacing: 18))
            : AnyLayout(HStackLayout(spacing: 18))

        return layout {
            // Cerrar.
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }

            timeDisplay

            speedMenu

            positionMenu
        }
        .padding(.vertical, panelPosition.isVertical ? 14 : 8)
        .padding(.horizontal, panelPosition.isVertical ? 8 : 14)
        .liquidGlass(in: Capsule(), interactive: true)
    }

    /// Tiempo actual / duración. En paneles laterales se apila en vertical.
    private var timeDisplay: some View {
        Group {
            if panelPosition.isVertical {
                VStack(spacing: 2) {
                    Text(currentTimeText)
                    Text(durationText).opacity(0.6)
                }
            } else {
                Text("\(currentTimeText) / \(durationText)")
            }
        }
        .font(.footnote.monospacedDigit())
        .foregroundStyle(.white.opacity(0.9))
        .allowsHitTesting(false)
    }

    /// Menú de velocidad de reproducción.
    private var speedMenu: some View {
        Menu {
            ForEach(speeds, id: \.self) { speed in
                Button {
                    setSpeed(speed)
                } label: {
                    if speed == playbackSpeed {
                        Label(Self.speedLabel(speed), systemImage: "checkmark")
                    } else {
                        Text(Self.speedLabel(speed))
                    }
                }
            }
        } label: {
            Text(Self.speedLabel(playbackSpeed))
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(.white)
                .frame(minWidth: 44, minHeight: 34)
                .contentShape(Rectangle())
        }
    }

    /// Menú para mover el panel a otro borde de la pantalla.
    private var positionMenu: some View {
        Menu {
            ForEach(PanelPosition.allCases, id: \.rawValue) { position in
                Button {
                    panelPositionRaw = position.rawValue
                } label: {
                    if position == panelPosition {
                        Label(position.title, systemImage: "checkmark")
                    } else {
                        Label(position.title, systemImage: position.icon)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
    }

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
        .liquidGlass(in: RoundedRectangle(cornerRadius: 20))
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

        // Velocidad recordada: play() reanuda siempre a defaultRate.
        player.defaultRate = Float(playbackSpeed)
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

    /// Cambia la velocidad; si está reproduciendo, aplica de inmediato.
    private func setSpeed(_ speed: Double) {
        playbackSpeed = speed
        player.defaultRate = Float(speed)
        if isPlaying {
            player.rate = Float(speed)
        }
        showFeedback("gauge.with.needle")
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

    /// "1×", "1.25×", "0.5×"…
    private static func speedLabel(_ speed: Double) -> String {
        if speed == speed.rounded() {
            return "\(Int(speed))×"
        }
        return "\(speed.formatted())×"
    }
}

// MARK: - Posición del panel de controles

/// Borde de la pantalla donde vive el panel de controles.
enum PanelPosition: String, CaseIterable {
    case top, bottom, leading, trailing

    var title: String {
        switch self {
        case .top: return "Arriba"
        case .bottom: return "Abajo"
        case .leading: return "Izquierda"
        case .trailing: return "Derecha"
        }
    }

    var icon: String {
        switch self {
        case .top: return "arrow.up.to.line"
        case .bottom: return "arrow.down.to.line"
        case .leading: return "arrow.left.to.line"
        case .trailing: return "arrow.right.to.line"
        }
    }

    var isVertical: Bool { self == .leading || self == .trailing }

    var alignment: Alignment {
        switch self {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }
}

// MARK: - Liquid Glass (iOS 26+) con fallback

/// Fondo Liquid Glass cuando el sistema lo soporta (iOS 26/27);
/// en versiones anteriores, fondo oscuro translúcido como antes.
private struct LiquidGlassBackground<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content.background(.black.opacity(0.45), in: shape)
        }
    }
}

extension View {
    func liquidGlass(in shape: some Shape, interactive: Bool = false) -> some View {
        modifier(LiquidGlassBackground(shape: shape, interactive: interactive))
    }
}
