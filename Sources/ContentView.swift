import SwiftUI
import UIKit

/// Sesión 0: pantalla mínima para validar el pipeline (compilar en GitHub -> .ipa -> iPhone).
struct ContentView: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 64))
            Text("D Video Player")
                .font(.largeTitle.bold())
            Text("Sesión 0 · pipeline OK")
            Text("v\(version) (build \(build)) · iOS \(UIDevice.current.systemVersion)")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
