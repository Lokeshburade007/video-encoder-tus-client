//
//  ZipHelper.swift
//  video-encoding-poc
//
//  Utility for zipping an encoded HLS folder (all variants + manifests)
//

import Foundation
import ZIPFoundation

enum ZipHelperError: Error {
    case failedToCreateArchive
}

enum ZipHelper {
    /// Create a ZIP archive from the contents of `sourceURL` (folder) at `zipFileURL`.
    static func zipFolder(sourceURL: URL, zipFileURL: URL) throws {
        let fm = FileManager.default

        if fm.fileExists(atPath: zipFileURL.path) {
            try fm.removeItem(at: zipFileURL)
        }

        let archive = try Archive(url: zipFileURL, accessMode: .create)

        guard let enumerator = fm.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues.isDirectory == true {
                continue
            }

            let relativePath = fileURL.path.replacingOccurrences(
                of: sourceURL.path + "/",
                with: ""
            )

            try archive.addEntry(
                with: relativePath,
                fileURL: fileURL,
                compressionMethod: .deflate
            )
        }
    }
}
