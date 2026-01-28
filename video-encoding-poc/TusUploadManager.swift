//
//  TusUploadManager.swift
//  video-encoding-poc
//
//  Simple wrapper around TUSKit's TUSClient for resumable uploads.
//

import Foundation
import TUSKit
internal import Combine

final class TusUploadManager: NSObject, ObservableObject {
    static let shared = TusUploadManager()

    private let client: TUSClient

    // MARK: - Published upload state (for UI)
    @Published var activeUploadId: UUID?
    @Published var activeProgress: Double = 0          // 0.0 - 1.0
    @Published var activeStatus: String = ""
    @Published var activeBytesUploaded: Int = 0
    @Published var activeTotalBytes: Int = 0
    @Published var lastUploadedURL: URL?

    override init() {
        // TODO: Replace with your own tus server URL.
        let serverURL = URL(string: "https://tusd.tusdemo.net/files")!

        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let storageDirectory = docs.appendingPathComponent("TUS", isDirectory: true)

        // Ensure storage directory exists
        try? fm.createDirectory(at: storageDirectory, withIntermediateDirectories: true)

        // Configure URLSession for TUS
        let configuration = URLSessionConfiguration.background(withIdentifier: "video-encoding-poc.uploads")
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 3

        // Initialize the client using the non-deprecated initializer (this can throw)
        do {
            let tmpClient = try TUSClient(
                server: serverURL,
                sessionIdentifier: "video-encoding-poc",
                sessionConfiguration: configuration,
                storageDirectory: storageDirectory,
                // chunkSize: 5 * 1024 * 1024 // 5 MB chunks
                supportedExtensions: [.creation]
            )
            client = tmpClient
        } catch {
            // If initialization fails, crash early with a clear message
            fatalError("Failed to initialize TUSClient: \(error)")
        }

        super.init()
        client.delegate = self
    }

    /// Start uploading a single file using TUS. Returns the upload ID.
    @discardableResult
    func upload(fileURL: URL, context: [String: String]? = nil) throws -> UUID {
        let id = try client.uploadFileAt(filePath: fileURL, context: context)

        DispatchQueue.main.async {
            self.activeUploadId = id
            self.activeProgress = 0
            self.activeStatus = "Starting upload…"
            self.activeBytesUploaded = 0
            self.activeTotalBytes = 0
        }

        TusUploadManager.postLog("TUS: queued upload id=\(id.uuidString) file=\(fileURL.lastPathComponent)")
        return id
    }

    // MARK: - Helper for broadcasting log messages to UI
    private static func postLog(_ message: String) {
        print(message)
        NotificationCenter.default.post(
            name: .tusLog,
            object: nil,
            userInfo: ["message": message]
        )
    }
}

// MARK: - TUSClientDelegate

extension TusUploadManager: TUSClientDelegate {
    func fileError(error: TUSKit.TUSClientError, client: TUSKit.TUSClient) {
        TusUploadManager.postLog("TUS: file error (no id) \(error)")
    }
    
    func didStartUpload(id: UUID, context: [String : String]?, client: TUSClient) {
        TusUploadManager.postLog("TUS: started upload id=\(id.uuidString)")

        DispatchQueue.main.async {
            self.activeUploadId = id
            self.activeStatus = "Uploading…"
        }
    }

    func didFinishUpload(id: UUID, url: URL, context: [String : String]?, client: TUSClient) {
        TusUploadManager.postLog("TUS: finished upload id=\(id.uuidString) url=\(url.absoluteString)")

        DispatchQueue.main.async {
            if self.activeUploadId == id {
                self.activeProgress = 1.0
                self.activeStatus = "Completed"
            }
            self.lastUploadedURL = url
        }
    }

    func uploadFailed(id: UUID, error: Error, context: [String : String]?, client: TUSClient) {
        TusUploadManager.postLog("TUS: upload failed id=\(id.uuidString) error=\(error)")

        DispatchQueue.main.async {
            if self.activeUploadId == id {
                self.activeStatus = "Failed"
            }
        }
    }

    func fileError(id: UUID?, error: TUSClientError, client: TUSClient) {
        TusUploadManager.postLog("TUS: file error \(error) id=\(id?.uuidString ?? "nil")")
    }

    func totalProgress(bytesUploaded: Int, totalBytes: Int, client: TUSClient) {
        // Optional: global progress – log for debugging
        TusUploadManager.postLog("TUS: totalProgress uploaded=\(bytesUploaded) / \(totalBytes) bytes")
    }

    func progressFor(
        id: UUID,
        context: [String : String]?,
        bytesUploaded: Int,
        totalBytes: Int,
        client: TUSClient
    ) {
        let progress = totalBytes > 0 ? Double(bytesUploaded) / Double(totalBytes) : 0
        let percent = Int(progress * 100)

        TusUploadManager.postLog(
            "TUS: progress id=\(id.uuidString) \(bytesUploaded)/\(totalBytes) bytes (\(percent)%)"
        )

        DispatchQueue.main.async {
            if self.activeUploadId == id {
                self.activeBytesUploaded = bytesUploaded
                self.activeTotalBytes = totalBytes
                self.activeProgress = progress
                self.activeStatus = "Uploading… \(percent)%"
            }
        }
    }
}

// Notification name for piping TUS logs into the SwiftUI log view.
extension Notification.Name {
    static let tusLog = Notification.Name("TusUploadLog")
}


