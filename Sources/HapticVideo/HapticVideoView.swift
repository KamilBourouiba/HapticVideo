import SwiftUI
import AVKit

public struct HapticVideoView: View {
    @ObservedObject var viewModel: HapticVideoViewModel
    @State private var showingVideoPicker = false
    @State private var showingHapticPicker = false
    @State private var showingIntensityControl = false
    
    public init(viewModel: HapticVideoViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            // Lecteur vidéo
            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .frame(height: 300)
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.7))
                    .frame(height: 300)
                    .overlay(Text("Aucune vidéo").foregroundColor(.white))
            }
            
            // Contrôles de lecture
            HStack(spacing: 20) {
                Button(action: {
                    viewModel.startPlayback()
                }) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                }
                Button(action: {
                    viewModel.pausePlayback()
                }) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                }
                Button(action: {
                    viewModel.stopPlayback()
                }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                }
                Button(action: {
                    showingIntensityControl = true
                }) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.purple)
                }
            }
            
            // Sélection de fichiers
            HStack(spacing: 20) {
                Button("Sélectionner une vidéo") {
                    showingVideoPicker = true
                }
                Button("Sélectionner un fichier haptique") {
                    showingHapticPicker = true
                }
            }
            
            // Informations sur les fichiers
            VStack(alignment: .leading, spacing: 10) {
                if let hapticName = viewModel.hapticFileName {
                    Text("Fichier haptique : \(hapticName)")
                        .foregroundColor(.green)
                }
                if let videoName = viewModel.videoFileName {
                    Text("Vidéo : \(videoName)")
                        .foregroundColor(.green)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            // Slider d'intensité
            if showingIntensityControl {
                VStack(spacing: 20) {
                    Text("Intensité Haptique")
                        .font(.headline)
                    Slider(value: Binding(
                        get: { viewModel.hapticMultiplier },
                        set: { viewModel.adjustHapticIntensity($0) }
                    ), in: 0...2)
                    .padding()
                    Text("Multiplicateur: \(String(format: "%.1f", viewModel.hapticMultiplier))x")
                        .foregroundColor(.secondary)
                    Button("Fermer") {
                        showingIntensityControl = false
                    }
                    .padding()
                }
                .padding()
            }
        }
        .padding()
        .sheet(isPresented: $showingVideoPicker) {
            DocumentPickerView(allowedTypes: ["public.movie"]) { urls in
                if let url = urls.first {
                    viewModel.loadVideo(url: url)
                }
            }
        }
        .sheet(isPresented: $showingHapticPicker) {
            DocumentPickerView(allowedTypes: ["public.json"]) { urls in
                if let url = urls.first {
                    viewModel.loadHapticFile(url: url)
                }
            }
        }
    }
}

// DocumentPickerView à ajouter dans le package pour la sélection de fichiers
public struct DocumentPickerView: UIViewControllerRepresentable {
    public var allowedTypes: [String]
    public var onDocumentsPicked: ([URL]) -> Void
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedTypes.compactMap { UTType(filenameExtension: $0) })
        picker.delegate = context.coordinator
        return picker
    }
    
    public func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    public class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView
        public init(_ parent: DocumentPickerView) { self.parent = parent }
        public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onDocumentsPicked(urls)
        }
    }
} 