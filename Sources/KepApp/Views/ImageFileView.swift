import SwiftUI
import AppKit
import KepBase

/// Standalone viewer for image files opened from the workspace — a zoomable
/// canvas with a dimensions + zoom% info bar and Fit / 100% controls.
struct ImageFileView: View {
    let url: URL
    @StateObject private var zoom = ImageZoomController()
    @State private var image: NSImage?

    /// Extensions we render in the image viewer (NSImage-decodable raster/vector).
    static let imageExtensions: Set<String> =
        ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif"]

    static func isImagePath(_ path: String) -> Bool {
        imageExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    var body: some View {
        Group {
            if let image {
                ZStack(alignment: .bottom) {
                    ZoomableImageView(image: image, controller: zoom)
                    infoBar(image)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
                    Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if image == nil { image = NSImage(contentsOfFile: url.path) } }
    }

    private func infoBar(_ img: NSImage) -> some View {
        HStack(spacing: 12) {
            Text("\(Int(img.size.width.rounded()))×\(Int(img.size.height.rounded())) px")
            Spacer()
            Text("\(Int((zoom.zoom * 100).rounded()))%")
                .monospacedDigit()
            Button(L("image.fit")) { zoom.fit() }
            Button(L("image.actual")) { zoom.actualSize() }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(8)
    }
}
