import SwiftUI
import AVFoundation
import UIKit

/// AVPlayerLayer envuelto para SwiftUI, sin controles del sistema.
/// Los gestos (tap y mantener+arrastrar) se manejan aquí con reconocedores
/// de UIKit, que son más confiables que la secuencia de gestos de SwiftUI
/// y no interfieren con los botones que están encima.
struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer
    var onTap: () -> Void
    var onScrubBegan: () -> Void
    /// Recibe el desplazamiento horizontal como fracción del ancho de la vista
    /// (1.0 = arrastró todo el ancho de la pantalla). Funciona igual al rotar.
    var onScrubMoved: (_ widthFraction: Double) -> Void
    var onScrubEnded: () -> Void

    func makeUIView(context: Context) -> PlayerLayerUIView {
        let view = PlayerLayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
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

        return view
    }

    func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {
        context.coordinator.parent = self
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: VideoLayerView
        private var startX: CGFloat = 0

        init(parent: VideoLayerView) { self.parent = parent }

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
    }
}

/// UIView cuya capa raíz es un AVPlayerLayer (se redimensiona sola).
final class PlayerLayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
