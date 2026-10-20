import SwiftUI
import UniformTypeIdentifiers

/// Sesión 1: elegir un MP4 desde la app Archivos y reproducirlo.
struct ContentView: View {
    @State private var video: VideoSelection?
    @State private var showPicker = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if let video {
                PlayerScreen(video: video, onClose: closeVideo)
                    .id(video.id)
            } else {
                welcomeScreen
            }
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.movie, .video],
            allowsMultipleSelection: false
        ) { result in
            handlePickerResult(result)
        }
    }

    private var welcomeScreen: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("D Video Player")
                .font(.largeTitle.bold())
            Button {
                showPicker = true
            } label: {
                Label("Abrir video", systemImage: "folder")
                    .font(.title3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    private func handlePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            errorMessage = nil
            // Acceso a archivos fuera del sandbox (security scoped).
            let accessing = url.startAccessingSecurityScopedResource()
            video = VideoSelection(url: url, isAccessingScopedResource: accessing)
        case .failure(let error):
            errorMessage = "No se pudo abrir el video: \(error.localizedDescription)"
        }
    }

    private func closeVideo() {
        video?.stopAccess()
        video = nil
    }
}

/// URL del video elegido + control del acceso security-scoped.
struct VideoSelection: Identifiable {
    let id = UUID()
    let url: URL
    let isAccessingScopedResource: Bool

    func stopAccess() {
        if isAccessingScopedResource {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

#Preview {
    ContentView()
}
