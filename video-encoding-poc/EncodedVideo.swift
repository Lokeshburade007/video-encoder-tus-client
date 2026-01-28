//
//  EncodedVideo.swift
//  video-encoding-poc
//
//  Created by Lokesh Burade on 28/01/26.
//

import Foundation

struct EncodedVideo: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let playlistURL: URL
}