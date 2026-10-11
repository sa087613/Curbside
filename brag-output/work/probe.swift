import AVFoundation
import AppKit
let u = URL(fileURLWithPath: CommandLine.arguments[1])
let asset = AVURLAsset(url: u)
print("duration", CMTimeGetSeconds(asset.duration))
for t in asset.tracks { print(t.mediaType.rawValue, t.naturalSize, t.nominalFrameRate, CMTimeGetSeconds(t.timeRange.duration)) }
let g = AVAssetImageGenerator(asset: asset); g.requestedTimeToleranceBefore = .zero; g.requestedTimeToleranceAfter = .zero
for s in [0.0, 7.5, 14.6] {
  let img = try g.copyCGImage(at: CMTime(seconds: s, preferredTimescale: 600), actualTime: nil)
  let rep = NSBitmapImageRep(cgImage: img)
  try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "probe-\(s).png"))
}
