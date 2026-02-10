//
//  LibraryView.swift
//  GestureFlow
//
//  Created by aristides lintzeris on 10/2/2026.
//


import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct LibraryView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var isShowingFilePicker = false
    @State private var isShowingVideoPicker = false

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Import")) {
                    Button(action: {
                        isShowingVideoPicker = true
                    }) {
                        Label("From Video Library", systemImage: "video.fill")
                    }
                    
                    Button(action: {
                        isShowingFilePicker = true
                    }) {
                        Label("From Files", systemImage: "folder.fill")
                    }
                }
                
                Section(header: Text("Streaming")) {
                    Button(action: {
                        // TODO: Implement MPMediaPickerController
                        print("Apple Music Tapped")
                    }) {
                        Label("From Apple Music", systemImage: "music.note")
                    }
                }
            }
            .navigationTitle("Select Media")
            .sheet(isPresented: $isShowingFilePicker) {
                DocumentPicker { url in
                    let title = url.lastPathComponent
                    coordinator.didSelectAudio(url: url, title: title)
                }
            }
            .sheet(isPresented: $isShowingVideoPicker) {
                VideoPicker { url in
                    let title = url.lastPathComponent
                    coordinator.didSelectAudio(url: url, title: title)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct VideoPicker: UIViewControllerRepresentable {
    var onSelect: (URL) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var parent: VideoPicker

        init(_ parent: VideoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let provider = results.first?.itemProvider else { return }
            
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    if let error = error {
                        print("Error loading video: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let url = url else { return }
                    
                    do {
                        let filename = url.lastPathComponent
                        let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                        
                        if FileManager.default.fileExists(atPath: localURL.path) {
                            try FileManager.default.removeItem(at: localURL)
                        }
                        try FileManager.default.copyItem(at: url, to: localURL)
                        
                        DispatchQueue.main.async {
                            self.parent.onSelect(localURL)
                        }
                    } catch {
                        print("Video copy error: \(error)")
                    }
                }
            }
        }
    }
}

// A helper to integrate UIDocumentPickerViewController into SwiftUI
struct DocumentPicker: UIViewControllerRepresentable {
    var onSelect: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.audio])
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // Security-Scoped Resource Handling: Copy the file to a local sandbox directory.
            let shouldStopAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if shouldStopAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            do {
                let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                // If a file already exists, remove it.
                if FileManager.default.fileExists(atPath: localURL.path) {
                    try FileManager.default.removeItem(at: localURL)
                }
                try FileManager.default.copyItem(at: url, to: localURL)
                parent.onSelect(localURL)
            } catch {
                print("Error copying file: \(error.localizedDescription)")
            }
        }
    }
}