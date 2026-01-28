//
//  VideoPicker_2.swift
//  video-encoding-poc
//
//  Created by Lokesh Burade on 28/01/26.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// A SwiftUI wrapper that presents the system photo picker to select a single video.
/// The selected video's temporary file URL is passed back via the `url` binding.
struct VideoPicker: UIViewControllerRepresentable {
    @Binding var url: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .videos
        configuration.selectionLimit = 1

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // No-op
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: VideoPicker

        init(_ parent: VideoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            defer { picker.dismiss(animated: true) }

            guard let provider = results.first?.itemProvider, provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
                parent.url = nil
                return
            }

            // Load the movie and write to a temporary file URL
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { fileURL, error in
                if let error = error {
                    print("VideoPicker error:", error.localizedDescription)
                    DispatchQueue.main.async { self.parent.url = nil }
                    return
                }

                guard let fileURL = fileURL else {
                    DispatchQueue.main.async { self.parent.url = nil }
                    return
                }

                // Copy to a stable temporary location, because the provided URL may be ephemeral.
                let tempDir = FileManager.default.temporaryDirectory
                let destination = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileURL.pathExtension)

                do {
                    // Remove destination if exists
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.copyItem(at: fileURL, to: destination)
                    DispatchQueue.main.async { self.parent.url = destination }
                } catch {
                    print("Failed to copy picked video:", error.localizedDescription)
                    DispatchQueue.main.async { self.parent.url = nil }
                }
            }
        }
    }
}
