//
//  TusUploadManager.swift
//  video-encoding-poc
//
//  Simple wrapper around TUSKit's TUSClient for resumable uploads.
//

import Foundation
import TUSKit

final class TusUploadManager: NSObject {
    static let shared = TusUploadManager()

    private let client: TUSClient

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
        try client.uploadFileAt(filePath: fileURL, context: context)
    }
}

// MARK: - TUSClientDelegate

extension TusUploadManager: TUSClientDelegate {
    func fileError(error: TUSKit.TUSClientError, client: TUSKit.TUSClient) {
        print("TUS: file error (no id) \(error)")
    }
    
    func didStartUpload(id: UUID, context: [String : String]?, client: TUSClient) {
        print("TUS: started upload \(id)")
    }

    func didFinishUpload(id: UUID, url: URL, context: [String : String]?, client: TUSClient) {
        print("TUS: finished upload \(id) url=\(url)")
    }

    func uploadFailed(id: UUID, error: Error, context: [String : String]?, client: TUSClient) {
        print("TUS: upload failed \(id) error=\(error)")
    }

    func fileError(id: UUID?, error: TUSClientError, client: TUSClient) {
        print("TUS: file error \(error) id=\(id?.uuidString ?? "nil")")
    }

    func totalProgress(bytesUploaded: Int, totalBytes: Int, client: TUSClient) {
        // Optional: global progress
    }

    func progressFor(
        id: UUID,
        context: [String : String]?,
        bytesUploaded: Int,
        totalBytes: Int,
        client: TUSClient
    ) {
        // Optional: per-upload progress
    }
}

