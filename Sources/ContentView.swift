import SwiftUI
import UniformTypeIdentifiers

/// Pantalla inicial: lista de videos de la carpeta de la app (visible en
/// Archivos → En mi iPhone → D Video Player) + botón para abrir un video
/// de cualquier otra carpeta con el selector del sistema.
struct ContentView: View {
    @State private var video: VideoSelection?
    @State private var showPicker = false
    @State private var errorMessage: String?
    @State private var videos: [VideoFile] = []

    var body: some View {
        ZStack {
            if let video {
                PlayerScreen(video: video, onClose: closeVideo)
                    .id(video.id)
            } else {
                library
            }
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.movie, .video],
            allowsMultipleSelection: false
        ) { result in
            handlePickerResult(result)
        }
        .alert("No se pudo abrir el video", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Biblioteca

    private var library: some View {
        NavigationStack {
            Group {
                if videos.isEmpty {
                    emptyState
                } else {
                    videoList
                }
            }
            .navigationTitle("D Video Player")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPicker = true
                    } label: {
                        Label("Abrir de otra carpeta", systemImage: "folder")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(Self.versionText)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }
        }
        .onAppear(perform: loadVideos)
    }

    private var videoList: some View {
        List(videos) { file in
            Button {
                play(file)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(file.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .refreshable { loadVideos() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Sin videos", systemImage: "film.stack")
        } description: {
            Text("Copia tus MP4 a la carpeta **D Video Player** en la app Archivos (En mi iPhone) y aparecerán aquí, o abre uno de otra carpeta.")
        } actions: {
            Button {
                showPicker = true
            } label: {
                Label("Abrir video", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Acciones

    /// Reproducir un video de la carpeta de la app (no requiere security scope).
    private func play(_ file: VideoFile) {
        video = VideoSelection(url: file.url, isAccessingScopedResource: false)
    }

    private func loadVideos() {
        videos = VideoLibrary.scan()
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
            errorMessage = error.localizedDescription
        }
    }

    private func closeVideo() {
        video?.stopAccess()
        video = nil
        loadVideos()
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    /// "v0.5.0 (build 5)" leído del Info.plist del bundle instalado.
    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (build \(build))"
    }
}

// MARK: - Biblioteca de videos (carpeta Documents de la app)

/// Un video dentro de la carpeta de la app.
struct VideoFile: Identifiable {
    let url: URL
    let size: Int64?
    let modified: Date?

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }

    var subtitle: String {
        var parts: [String] = []
        if let size {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if let modified {
            parts.append(modified.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.joined(separator: " · ")
    }
}

enum VideoLibrary {
    private static let videoExtensions: Set<String> = ["mp4", "m4v", "mov"]

    /// Lista los videos de Documents (la carpeta visible en Archivos).
    static func scan() -> [VideoFile] {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }
        let urls = (try? fm.contentsOfDirectory(
            at: docs,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { videoExtensions.contains($0.pathExtension.lowercased()) }
            .map { url in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                return VideoFile(
                    url: url,
                    size: values?.fileSize.map(Int64.init),
                    modified: values?.contentModificationDate
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
