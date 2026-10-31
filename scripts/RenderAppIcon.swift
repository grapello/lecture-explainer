//
//  RenderAppIcon.swift
//  Lexia
//
//  Renders LexiaLogo (Lecture-Explainer/Views/LexiaLogo.swift) into the app icon
//  PNGs. Run scripts/render-app-icon.sh, not this file directly.
//

import AppKit
import CoreGraphics
import SwiftUI

@main
struct RenderAppIcon {
    @MainActor
    static func main() throws {
        let folder = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
        let files: [(LexiaLogo.IconLook, String)] = [(.light, "AppIcon.png"),
                                                    (.dark, "AppIcon-Dark.png"),
                                                    (.tinted, "AppIcon-Tinted.png")]
        for (look, name) in files {
            // 1024 × 1024 pixels: iOS makes every smaller size from this one.
            let renderer = ImageRenderer(content: LexiaLogo(style: .icon(look))
                .frame(width: 1024, height: 1024))
            renderer.scale = 1
            guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
            // App icons must have no transparency, so the image is drawn onto an
            // opaque bitmap (RGB, no alpha channel) before it is saved.
            let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
            let png = NSBitmapImageRep(cgImage: context.makeImage()!)
                .representation(using: .png, properties: [:])!
            try png.write(to: folder.appending(path: name))
            print("Wrote \(name)")
        }
    }
}
