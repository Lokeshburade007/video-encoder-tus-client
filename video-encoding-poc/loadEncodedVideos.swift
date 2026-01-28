//
//  loadEncodedVideos.swift
//  video-encoding-poc
//
//  Created by Lokesh Burade on 28/01/26.
//

import Foundation

func loadEncodedVideos() -> [EncodedVideo] {
    let fm = FileManager.default
    let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!

    guard let folders = try? fm.contentsOfDirectory(
        at: docs,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    return folders
        .filter { folder in
            fm.fileExists(
                atPath: folder.appendingPathComponent("manifest.m3u8").path
            )
        }
        .sorted { $0.lastPathComponent > $1.lastPathComponent }
        .map { folder in
            EncodedVideo(
                title: folder.lastPathComponent,
                playlistURL: folder.appendingPathComponent("manifest.m3u8")
            )
        }
}
