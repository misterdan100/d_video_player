import SwiftUI
import AVFoundation
import UIKit

/// AVPlayerLayer envuelto para SwiftUI, sin controles del sistema.
/// Los gestos se manejan aquí con reconocedores de UIKit, que son más
/// confiables que la secuencia de gestos de SwiftUI y no interfieren
/// con los botones que están encima.
/// - Tap (1 dedo) = play/pause. Mantener+arrastrar (1 dedo) = scrub.
/// - Pellizco (2 dedos) = zoom, como a una foto. Arrastre con 2 dedos = mover
///   el video cuando está con zoom. El zoom se mantiene hasta que se cambia
///   el modo de escala o se reinicia (zoomResetToken).
struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer
    /// Modo de escala del video (normal / llenar / estirar).
    var videoGravity: AVLayerVideoGravity
    /// Al cambiar este valor, el zoom de pellizco vuelve a 1× (animado).
    var zoomResetToken: Int
    var onTap: () -> Void
    var onScrubBegan: () -> Void
    /// Recibe el desplazamiento horizontal como fracción del ancho de la vista
    /// (1.0 = arrastró todo el ancho de la pantalla). Funciona igual al rotar.
    var onScrubMoved: (_ widthFraction: Double) -> Void
    var onScrubEnded: () -> Void

    func makeUIView(context: Context) -> VideoGestureContainerView {
        let view = VideoGestureContainerView()
        view.videoView.playerLayer.player = player
        view.videoView.playerLayer.videoGravity = videoGravity
        view.backgroundColor = .black
        view.clipsToBounds = true
        view.isUserInteractionEnabled = true

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        view.addGestureRecognizer(tap)

        // Mantener presionado 0.3 s activa el scrub; después el mismo dedo
        // puede arrastrarse libremente (states .began → .changed → .ended).
        let press = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        press.minimumPressDuration = 0.3
        view.addGestureRecognizer(press)

        // Zoom con pellizco (2 dedos), anclado al punto entre los dedos.
        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        // Mover el video con 2 dedos cuando está con zoom
        // (1 dedo queda reservado para play/pause y scrub).
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        return view
    }

    func updateUIView(_ uiView: VideoGestureContainerView, context: Context) {
        context.coordinator.parent = self
        if uiView.videoView.playerLayer.player !== player {
            uiView.videoView.playerLayer.player = player
        }
        if uiView.videoView.playerLayer.videoGravity != videoGravity {
            uiView.videoView.playerLayer.videoGravity = videoGravity
        }
        if context.coordinator.lastZoomResetToken != zoomResetToken {
            context.coordinator.lastZoomResetToken = zoomResetToken
            uiView.resetZoom(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: VideoLayerView
        var lastZoomResetToken: Int
        private var startX: CGFloat = 0

        init(parent: VideoLayerView) {
            self.parent = parent
            self.lastZoomResetToken = parent.zoomResetToken
        }

        @objc func handleTap() {
            parent.onTap()
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let view = gesture.view else { return }
            switch gesture.state {
            case .began:
                startX = gesture.location(in: view).x
                parent.onScrubBegan()
            case .changed:
                let dx = gesture.location(in: view).x - startX
                let width = max(view.bounds.width, 1)
                parent.onScrubMoved(Double(dx / width))
            case .ended, .cancelled, .failed:
                parent.onScrubEnded()
            default:
                break
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let view = gesture.view as? VideoGestureContainerView else { return }
            switch gesture.state {
            case .changed:
                view.pinch(by: gesture.scale, at: gesture.location(in: view))
                gesture.scale = 1
            case .ended, .cancelled, .failed:
                view.settleAfterGesture()
            default:
                break
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view as? VideoGestureContainerView else { return }
            switch gesture.state {
            case .changed:
                let t = gesture.translation(in: view)
                view.pan(by: t)
                gesture.setTranslation(.zero, in: view)
            case .ended, .cancelled, .failed:
                view.settleAfterGesture()
            default:
                break
            }
        }

        /// Pellizco y arrastre de 2 dedos funcionan a la vez (como en Fotos).
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            let isZoomPair = (gestureRecognizer is UIPinchGestureRecognizer
                              || gestureRecognizer is UIPanGestureRecognizer)
                && (other is UIPinchGestureRecognizer || other is UIPanGestureRecognizer)
            return isZoomPair
        }
    }
}

/// Contenedor que aloja la vista del video y le aplica el zoom de pellizco
/// (escala + desplazamiento) con un CGAffineTransform.
final class VideoGestureContainerView: UIView {
    /// La vista cuyo layer raíz es el AVPlayerLayer.
    let videoView = PlayerLayerUIView()

    private(set) var zoomScale: CGFloat = 1
    private(set) var zoomOffset: CGPoint = .zero

    /// Límites del zoom de pellizco.
    static let minZoom: CGFloat = 1
    static let maxZoom: CGFloat = 6

    override init(frame: CGRect) {
        super.init(frame: frame)
        videoView.isUserInteractionEnabled = false
        addSubview(videoView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no implementado") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Layout manual con bounds/center (no autoresizing): con un transform
        // activo, el frame es indefinido en UIKit y el autoresizing falla.
        videoView.bounds = bounds
        videoView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        // Al rotar o cambiar de tamaño, mantener el desplazamiento dentro de rango.
        clampOffset()
        applyTransform()
    }

    /// Escala alrededor del punto del pellizco (el contenido bajo los dedos
    /// se queda bajo los dedos), con límites y clamping del desplazamiento.
    func pinch(by factor: CGFloat, at location: CGPoint) {
        let newScale = min(max(zoomScale * factor, Self.minZoom), Self.maxZoom)
        guard newScale != zoomScale else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let p = CGPoint(x: location.x - center.x, y: location.y - center.y)
        let ratio = newScale / zoomScale
        zoomOffset = CGPoint(
            x: p.x - (p.x - zoomOffset.x) * ratio,
            y: p.y - (p.y - zoomOffset.y) * ratio
        )
        zoomScale = newScale
        clampOffset()
        applyTransform()
    }

    /// Mueve el video (solo tiene efecto cuando hay zoom).
    func pan(by translation: CGPoint) {
        guard zoomScale > 1 else { return }
        zoomOffset.x += translation.x
        zoomOffset.y += translation.y
        clampOffset()
        applyTransform()
    }

    /// Redondeos al soltar: si quedó casi en 1×, vuelve exacto a 1×.
    func settleAfterGesture() {
        if zoomScale < 1.02 {
            resetZoom(animated: true)
        }
    }

    /// Vuelve al zoom normal (1×, centrado).
    func resetZoom(animated: Bool) {
        zoomScale = 1
        zoomOffset = .zero
        if animated {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
                self.applyTransform()
            }
        } else {
            applyTransform()
        }
    }

    /// Evita que el video se despegue de los bordes al moverlo:
    /// el desplazamiento máximo depende de cuánto zoom hay.
    private func clampOffset() {
        let maxX = bounds.width * (zoomScale - 1) / 2
        let maxY = bounds.height * (zoomScale - 1) / 2
        zoomOffset.x = min(max(zoomOffset.x, -maxX), maxX)
        zoomOffset.y = min(max(zoomOffset.y, -maxY), maxY)
    }

    private func applyTransform() {
        videoView.transform = CGAffineTransform(translationX: zoomOffset.x, y: zoomOffset.y)
            .scaledBy(x: zoomScale, y: zoomScale)
    }
}

/// UIView cuya capa raíz es un AVPlayerLayer (se redimensiona sola).
final class PlayerLayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
