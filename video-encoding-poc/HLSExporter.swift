import Foundation
import FFmpegSupport

enum HLSExporterError: LocalizedError {
    case invalidDocumentsDirectory
    case failedToCreateDirectory(URL)
    case ffmpegFailed(exitCode: Int32, stage: String)
    case failedToWriteMasterPlaylist(URL)

    var errorDescription: String? {
        switch self {
        case .invalidDocumentsDirectory:
            return "Documents directory not found."
        case .failedToCreateDirectory(let url):
            return "Failed to create directory: \(url.path)"
        case .ffmpegFailed(let exitCode, let stage):
            return "FFmpeg failed (\(stage)) with exit code \(exitCode)."
        case .failedToWriteMasterPlaylist(let url):
            return "Failed to write master playlist: \(url.path)"
        }
    }
}


struct HLSExporter {
    struct Variant {
        let name: String          // "1080p"
        let width: Int            // 1920
        let height: Int           // 1080
        let videoBitrate: String  // "5000k"
        let maxrate: String       // "5350k"
        let bufsize: String       // "7500k"
        let bandwidth: Int        // for master manifest
        let avgBandwidth: Int     // for master manifest
        let codecs: String        // for master manifest
    }

    static func encodeToHLS(
        inputURL: URL,
        log: @escaping (String) async -> Void
    ) async throws -> URL {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw HLSExporterError.invalidDocumentsDirectory
        }

        let outFolder = docs.appendingPathComponent(timestampFolderName(), isDirectory: true)
        try createDirectoryIfNeeded(outFolder)

        let variants: [Variant] = [
            Variant(
                name: "1080p",
                width: 1920,
                height: 1080,
                videoBitrate: "5000k",
                maxrate: "5350k",
                bufsize: "7500k",
                bandwidth: 6000000,
                avgBandwidth: 5000000,
                codecs: "avc1.640028,mp4a.40.2"
            ),
            Variant(
                name: "720p",
                width: 1280,
                height: 720,
                videoBitrate: "2800k",
                maxrate: "2996k",
                bufsize: "4200k",
                bandwidth: 3500000,
                avgBandwidth: 2800000,
                codecs: "avc1.64001F,mp4a.40.2"
            ),
            Variant(
                name: "480p",
                width: 854,
                height: 480,
                videoBitrate: "1400k",
                maxrate: "1498k",
                bufsize: "2100k",
                bandwidth: 2000000,
                avgBandwidth: 1400000,
                codecs: "avc1.64001E,mp4a.40.2"
            )
        ]

        for v in variants {
            let vDir = outFolder.appendingPathComponent(v.name, isDirectory: true)
            try createDirectoryIfNeeded(vDir)

            let playlistURL = vDir.appendingPathComponent("index.m3u8")
            let segmentPattern = vDir.appendingPathComponent("segment_%03d.ts").path

            await log("Encoding \(v.name)...")
            await log("Output: \(playlistURL.path)")

            // Note:
            // - scale+pad keeps aspect ratio and produces exact target dimensions.
            // - independent_segments helps players switch variants.
            // - VOD playlist (not live).

            let args: [String] = [
                "-y",
                "-i", inputURL.path,

                "-vf",
                "format=yuv420p,scale=w=\(v.width):h=\(v.height):force_original_aspect_ratio=decrease,pad=\(v.width):\(v.height):(ow-iw)/2:(oh-ih)/2",

                "-c:v", "h264_videotoolbox",
                "-profile:v", "main",
                "-level", "4.0",
                "-pix_fmt", "yuv420p",
                "-allow_sw", "1",

                "-b:v", v.videoBitrate,
                "-maxrate", v.maxrate,
                "-bufsize", v.bufsize,

                "-g", "48",
                "-sc_threshold", "0",

                "-c:a", "aac",
                "-profile:a", "aac_low",
                "-b:a", "128k",
                "-ac", "2",
                "-ar", "48000",

                "-hls_time", "6",
                "-hls_playlist_type", "vod",
                "-hls_flags", "independent_segments",
                "-hls_segment_filename", segmentPattern,

                playlistURL.path
            ]


            await log(args.joined(separator: " "))


            // FFmpeg-iOS readme style: ffmpeg(["ffmpeg", ...])
            let exitCode = ffmpeg(args)
            if exitCode != 0 {
                await log("❌ \(v.name) failed with exitCode=\(exitCode)")
                throw HLSExporterError.ffmpegFailed(exitCode: Int32(exitCode), stage: v.name)
            }

            await log("✅ \(v.name) done")
        }

        let masterURL = outFolder.appendingPathComponent("manifest.m3u8")
        let master = buildMasterPlaylist(variants: variants)
        do {
            try master.write(to: masterURL, atomically: true, encoding: .utf8)
        } catch {
            throw HLSExporterError.failedToWriteMasterPlaylist(masterURL)
        }

        await log("Master playlist: \(masterURL.path)")
        return outFolder
    }

    private static func createDirectoryIfNeeded(_ url: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue { return }
        }
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw HLSExporterError.failedToCreateDirectory(url)
        }
    }

    private static func timestampFolderName(now: Date = Date()) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd-hh-mm-a"
        return df.string(from: now)
    }

    private static func buildMasterPlaylist(variants: [Variant]) -> String {
        var lines: [String] = []
        lines.append("#EXTM3U")
        lines.append("#EXT-X-VERSION:3")

        for v in variants {
            lines.append(
                "#EXT-X-STREAM-INF:BANDWIDTH=\(v.bandwidth),AVERAGE-BANDWIDTH=\(v.avgBandwidth),RESOLUTION=\(v.width)x\(v.height),CODECS=\"\(v.codecs)\""
            )
            lines.append("\(v.name)/index.m3u8")
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }
}

