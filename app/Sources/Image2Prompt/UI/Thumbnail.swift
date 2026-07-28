import AppKit
import SwiftUI

/// 缩略图加载。用 NSImage 的降采样读取，不把整张原图读进内存——
/// 参考图动辄 4000px 宽，一次拖 20 张按原尺寸解码会直接卡住界面。
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private var cache: [URL: NSImage] = [:]

    func thumbnail(for url: URL, maxPixel: CGFloat = 256) async -> NSImage? {
        if let hit = cache[url] { return hit }

        // 只把 CGImage 跨线程传回来，NSImage 在主线程构造。
        // NSImage 不是 Sendable（内部有可变状态），CGImage 是不可变的，跨线程安全。
        let boxed = await Task.detached(priority: .utility) {
            Self.downsample(url: url, maxPixel: maxPixel)
        }.value

        guard let boxed else { return nil }
        let image = NSImage(
            cgImage: boxed.cgImage,
            size: NSSize(width: boxed.cgImage.width, height: boxed.cgImage.height))
        cache[url] = image
        return image
    }

    /// CGImage 不可变，跨线程安全，但没有正式的 Sendable 标注
    private struct CGImageBox: @unchecked Sendable {
        let cgImage: CGImage
    }

    nonisolated private static func downsample(url: URL, maxPixel: CGFloat) -> CGImageBox? {
        guard
            let src = CGImageSourceCreateWithURL(
                url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            return nil
        }
        return CGImageBox(cgImage: cg)
    }
}

struct ThumbnailView: View {
    let url: URL
    var size: CGFloat = 56

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: url) {
            image = await ThumbnailCache.shared.thumbnail(for: url, maxPixel: size * 3)
        }
    }
}
