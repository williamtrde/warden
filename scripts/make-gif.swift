// Assembles PNG frames into a looping GIF: make-gif.swift <output.gif> <width> <seconds per frame> <frame.png>...
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count > 4, let width = Int(arguments[2]), let delay = Double(arguments[3]) else {
    FileHandle.standardError.write(Data("usage: make-gif.swift <output.gif> <width> <delay> <frames...>\n".utf8))
    exit(2)
}
let frames = Array(arguments[4...])
let output = URL(fileURLWithPath: arguments[1]) as CFURL
guard let destination = CGImageDestinationCreateWithURL(output, UTType.gif.identifier as CFString, frames.count, nil) else { exit(1) }
CGImageDestinationSetProperties(destination, [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
] as CFDictionary)
let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
let options = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceThumbnailMaxPixelSize: width,
    kCGImageSourceCreateThumbnailWithTransform: true
] as CFDictionary
for frame in frames {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: frame) as CFURL, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { exit(1) }
    CGImageDestinationAddImage(destination, image, frameProperties)
}
exit(CGImageDestinationFinalize(destination) ? 0 : 1)
