
import SwiftUI
import AVKit
import UIKit

struct ContentView: View {

    @State private var selectedVideoURL: URL?
    @State private var showVideoPicker = false
    @State private var isEncoding = false
    @State private var encodeLog: String = ""

    // Encoded videos list
    @State private var encodedVideos: [EncodedVideo] = []

    // Currently playing encoded video
    @State private var selectedEncodedVideo: EncodedVideo?

    // ZIP export
    @State private var zipURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        VStack(spacing: 16) {

            // MARK: - Header
            Text("HLS Video Encoder")
                .font(.headline)

            // MARK: - Pick Video
            Button("Select Video") {
                showVideoPicker = true
            }

            if let url = selectedVideoURL {
                Text("Selected: \(url.lastPathComponent)")
                    .font(.caption)
            }

            // MARK: - Encode Button
            Button(isEncoding ? "Encoding..." : "Encode to HLS") {
                startEncoding()
            }
            .disabled(isEncoding || selectedVideoURL == nil)

            Divider()

            // MARK: - Video Player
            if let video = selectedEncodedVideo {
                VideoPlayer(player: AVPlayer(url: video.playlistURL))
                    .frame(height: 220)
                    .cornerRadius(12)

                Text(video.title)
                    .font(.caption)

                // Download ZIP button for the currently selected encoded video
                Button {
                    createZip(for: video)
                } label: {
                    Label("Download ZIP", systemImage: "arrow.down.circle")
                }
                .padding(.top, 4)

                // Upload ZIP using TUS (resumable upload)
                Button {
                    uploadZip(for: video)
                } label: {
                    Label("Upload ZIP (TUS)", systemImage: "arrow.up.circle")
                }
                .padding(.top, 2)
            }

            // MARK: - Encoded Videos List
            if !encodedVideos.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Encoded Videos")
                        .font(.subheadline)
                        .bold()

                    ForEach(encodedVideos) { video in
                        Button {
                            selectedEncodedVideo = video
                        } label: {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                Text(video.title)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // MARK: - Logs
            ScrollView {
                Text(encodeLog.isEmpty ? "Logs will appear here." : encodeLog)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 160)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3))
            )
        }
        .padding()
        .sheet(isPresented: $showVideoPicker) {
            VideoPicker(url: $selectedVideoURL)
        }
        .sheet(isPresented: $showShareSheet) {
            if let zipURL {
                ActivityView(activityItems: [zipURL])
            }
        }
    }

    // MARK: - Encoding Logic
    private func startEncoding() {
        guard let input = selectedVideoURL else { return }

        isEncoding = true
        encodeLog = "Starting HLS encode...\n"

        Task.detached(priority: .userInitiated) {
            do {
                let outputFolder = try await HLSExporter.encodeToHLS(
                    inputURL: input,
                    log: { line in
                        await MainActor.run {
                            encodeLog += line + "\n"
                        }
                    }
                )

                // Use the master manifest at the root of the folder
                let playlistURL = outputFolder.appendingPathComponent("manifest.m3u8")

                let encoded = EncodedVideo(
                    title: input.lastPathComponent,
                    playlistURL: playlistURL
                )

                await MainActor.run {
                    encodedVideos.insert(encoded, at: 0)
                    selectedEncodedVideo = encoded
                    isEncoding = false
                    encodeLog += "✅ Encoding finished\n"
                }
            } catch {
                await MainActor.run {
                    encodeLog += "❌ \(error.localizedDescription)\n"
                    isEncoding = false
                }
            }
        }
    }

    // MARK: - ZIP Creation
    private func createZip(for video: EncodedVideo) {
        let folderURL = video.playlistURL.deletingLastPathComponent()

        guard let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return
        }

        let zipFileName = folderURL.lastPathComponent + ".zip"
        let destination = docs.appendingPathComponent(zipFileName)

        encodeLog += "Preparing ZIP: \(zipFileName)\n"

        Task.detached(priority: .userInitiated) {
            do {
                try await ZipHelper.zipFolder(sourceURL: folderURL, zipFileURL: destination)

                await MainActor.run {
                    self.zipURL = destination
                    self.showShareSheet = true
                    self.encodeLog += "✅ ZIP ready: \(zipFileName)\n"
                }
            } catch {
                await MainActor.run {
                    self.encodeLog += "❌ Failed to create ZIP: \(error.localizedDescription)\n"
                }
            }
        }
    }

    // MARK: - TUS Upload
    private func uploadZip(for video: EncodedVideo) {
        let folderURL = video.playlistURL.deletingLastPathComponent()

        guard let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return
        }

        let zipFileName = folderURL.lastPathComponent + ".zip"
        let destination = docs.appendingPathComponent(zipFileName)

        encodeLog += "Preparing ZIP for TUS upload: \(zipFileName)\n"

        Task.detached(priority: .userInitiated) {
            do {
                let fm = FileManager.default
                if !fm.fileExists(atPath: destination.path) {
                    try await ZipHelper.zipFolder(sourceURL: folderURL, zipFileURL: destination)
                }

                let uploadId = try await TusUploadManager.shared.upload(
                    fileURL: destination,
                    context: ["title": video.title]
                )

                await MainActor.run {
                    self.encodeLog += "📤 Started TUS upload id=\(uploadId.uuidString)\n"
                }
            } catch {
                await MainActor.run {
                    self.encodeLog += "❌ Failed to start TUS upload: \(error.localizedDescription)\n"
                }
            }
        }
    }
}

// MARK: - UIKit Share Sheet Wrapper
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

