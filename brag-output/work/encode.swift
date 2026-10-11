// swift encode.swift <framesDir> <audio.wav> <out.mp4> <fps>
import AVFoundation
import CoreGraphics
import ImageIO

let a = CommandLine.arguments
let framesDir = URL(fileURLWithPath: a[1]), audioURL = URL(fileURLWithPath: a[2]), outURL = URL(fileURLWithPath: a[3])
let fps = Int32(a[4])!
let files = try FileManager.default.contentsOfDirectory(atPath: framesDir.path).filter { $0.hasPrefix("f") && $0.hasSuffix(".png") }.sorted()
try? FileManager.default.removeItem(at: outURL)
let W = 1920, H = 1080

let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
  AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
  AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 14_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                    AVVideoMaxKeyFrameIntervalKey: 30],
  AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2, AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]])
vIn.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [
  kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000])
aIn.expectsMediaDataInRealTime = false
writer.add(vIn); writer.add(aIn)

let asset = AVURLAsset(url: audioURL)
let reader = try AVAssetReader(asset: asset)
let track = asset.tracks(withMediaType: .audio)[0]
let rOut = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
reader.add(rOut)

writer.startWriting(); reader.startReading(); writer.startSession(atSourceTime: .zero)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
var vi = 0, vDone = false, aDone = false
while !(vDone && aDone) {
  var progressed = false
  if !vDone && vIn.isReadyForMoreMediaData {
    if vi < files.count {
      let src = CGImageSourceCreateWithURL(framesDir.appendingPathComponent(files[vi]) as CFURL, nil)!
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
      var pb: CVPixelBuffer?
      CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
      CVPixelBufferLockBaseAddress(pb!, [])
      let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb!), width: W, height: H, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb!), space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
      ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
      CVPixelBufferUnlockBaseAddress(pb!, [])
      adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(vi), timescale: fps))
      vi += 1
    } else { vIn.markAsFinished(); vDone = true }
    progressed = true
  }
  if !aDone && aIn.isReadyForMoreMediaData {
    if let sb = rOut.copyNextSampleBuffer() { aIn.append(sb) } else { aIn.markAsFinished(); aDone = true }
    progressed = true
  }
  if !progressed { usleep(2000) }
}
let sem = DispatchSemaphore(value: 0)
writer.finishWriting { sem.signal() }
sem.wait()
print(writer.status == .completed ? "wrote \(outURL.path) (\(files.count) frames)" : "failed: \(String(describing: writer.error))")
