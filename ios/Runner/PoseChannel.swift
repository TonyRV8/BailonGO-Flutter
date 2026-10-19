import AVFoundation
import Accelerate
import Flutter
import MediaPipeTasksVision
import UIKit

/// Platform channel `bailongo/pose` para iOS: port de `MainActivity.kt`.
///
/// Envuelve MediaPipe Tasks Vision PoseLandmarker (modelo
/// pose_landmarker_lite.task, 33 landmarks BlazePose, doc 6.1) con el mismo
/// contrato que Android:
///  - `detect`: fotograma BGRA del plugin `camera` (camera_avfoundation ya lo
///    entrega derecho; la frontal llega espejada y se des-espeja aquí para que
///    los landmarks coincidan con Android). Devuelve [x,y,z,visibility] x 33
///    como Float64List.
///  - `processVideo`: {aspect, frames} muestreando ~30 fps.
///  - `videoThumbnail`: JPEG del fotograma central.
///
/// La inferencia corre en una cola serial (modo VIDEO exige orden) y nunca en
/// el hilo principal, que compone la preview de cámara (RNF-04).
final class PoseChannel: NSObject, FlutterPlugin {

  private static let channelName = "bailongo/pose"

  private var landmarker: PoseLandmarker?

  /// Una sola cola: MediaPipe en modo VIDEO exige fotogramas en orden.
  private var poseQueue: DispatchQueue?

  /// Timestamp monotónico creciente exigido por `detect(videoFrame:)`.
  private var lastTimestampMs = 0

  // Buffers reutilizados entre fotogramas para no asignar ~1 MB por frame.
  private var pixelBuffer: CVPixelBuffer?
  private var scratch: UnsafeMutableRawPointer?
  private var scratchSize = 0

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(PoseChannel(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "init":
      do {
        try initLandmarker()
        result(nil)
      } catch {
        result(FlutterError(code: "INIT_FAILED", message: "\(error)", details: nil))
      }

    case "detect":
      guard let bytes = (args?["bytes"] as? FlutterStandardTypedData)?.data,
        let width = args?["width"] as? Int,
        let height = args?["height"] as? Int
      else {
        result(FlutterError(code: "BAD_ARGS", message: "bytes/width/height requeridos", details: nil))
        return
      }
      let rotation = args?["rotation"] as? Int ?? 0
      let mirrored = args?["mirrored"] as? Bool ?? false
      guard let queue = poseQueue else {
        result(FlutterError(code: "NOT_INITIALIZED", message: "landmarker no inicializado", details: nil))
        return
      }
      queue.async {
        do {
          let out = try self.detect(
            bytes, width: width, height: height, rotation: rotation, mirrored: mirrored)
          let data = out.withUnsafeBufferPointer { Data(buffer: $0) }
          DispatchQueue.main.async { result(FlutterStandardTypedData(float64: data)) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "DETECT_FAILED", message: "\(error)", details: nil))
          }
        }
      }

    case "processVideo":
      guard let path = args?["path"] as? String else {
        result(FlutterError(code: "BAD_ARGS", message: "path requerido", details: nil))
        return
      }
      // Pesado: fuera del hilo principal, respuesta en main.
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let out = try self.processVideo(path)
          DispatchQueue.main.async { result(out) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "VIDEO_FAILED", message: "\(error)", details: nil))
          }
        }
      }

    case "videoThumbnail":
      guard let path = args?["path"] as? String else {
        result(FlutterError(code: "BAD_ARGS", message: "path requerido", details: nil))
        return
      }
      DispatchQueue.global(qos: .utility).async {
        let bytes = self.videoThumbnail(path)
        DispatchQueue.main.async {
          result(bytes.map { FlutterStandardTypedData(bytes: $0) })
        }
      }

    case "close":
      closeLandmarker()
      result(nil)

    case "keepScreenOn":
      // Durante la evaluación el usuario baila lejos del teléfono sin tocarlo:
      // sin esto iOS oscurece y bloquea la pantalla a media toma.
      UIApplication.shared.isIdleTimerDisabled = args?["on"] as? Bool ?? false
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Landmarker

  private static func makeLandmarker() throws -> PoseLandmarker {
    guard let path = Bundle.main.path(forResource: "pose_landmarker_lite", ofType: "task") else {
      throw PoseError("pose_landmarker_lite.task no está en el bundle")
    }
    let options = PoseLandmarkerOptions()
    options.baseOptions.modelAssetPath = path
    options.baseOptions.delegate = .CPU
    // VIDEO reutiliza el seguimiento entre fotogramas; IMAGE relanzaba el
    // detector de persona en cada uno.
    options.runningMode = .video
    options.minPoseDetectionConfidence = 0.5
    options.minPosePresenceConfidence = 0.5
    options.minTrackingConfidence = 0.5
    options.numPoses = 1
    return try PoseLandmarker(options: options)
  }

  private func initLandmarker() throws {
    if poseQueue == nil {
      poseQueue = DispatchQueue(label: "bailongo.pose", qos: .userInitiated)
    }
    if landmarker != nil { return }
    landmarker = try PoseChannel.makeLandmarker()
    lastTimestampMs = 0
  }

  private func closeLandmarker() {
    // Se libera dentro de la cola para no soltar el modelo a media inferencia.
    let queue = poseQueue
    poseQueue = nil
    let release = {
      self.landmarker = nil
      self.pixelBuffer = nil
      self.scratch?.deallocate()
      self.scratch = nil
      self.scratchSize = 0
      self.lastTimestampMs = 0
    }
    if let queue = queue { queue.async(execute: release) } else { release() }
  }

  // MARK: - detect

  /// Corre en [poseQueue]. Devuelve [x,y,z,visibility] x 33, o vacío si no hay
  /// cuerpo. Coordenadas normalizadas 0..1 sobre la imagen ya vertical.
  private func detect(
    _ bytes: Data, width: Int, height: Int, rotation: Int, mirrored: Bool
  ) throws -> [Double] {
    guard let lm = landmarker, width > 0, height > 0 else { return [] }
    // El plugin manda el plano completo: puede traer relleno al final de fila.
    let srcRowBytes = bytes.count / height
    guard srcRowBytes >= width * 4 else { return [] }

    let swap = rotation == 90 || rotation == 270
    let dstW = swap ? height : width
    let dstH = swap ? width : height
    guard let pb = reusablePixelBuffer(width: dstW, height: dstH) else { return [] }

    CVPixelBufferLockBaseAddress(pb, [])
    defer { CVPixelBufferUnlockBaseAddress(pb, []) }
    guard let dstBase = CVPixelBufferGetBaseAddress(pb) else { return [] }
    var dst = vImage_Buffer(
      data: dstBase, height: vImagePixelCount(dstH), width: vImagePixelCount(dstW),
      rowBytes: CVPixelBufferGetBytesPerRow(pb))

    let err: vImage_Error = bytes.withUnsafeBytes { raw -> vImage_Error in
      var src = vImage_Buffer(
        data: UnsafeMutableRawPointer(mutating: raw.baseAddress!),
        height: vImagePixelCount(height), width: vImagePixelCount(width),
        rowBytes: srcRowBytes)
      // Primero se deshace el espejo (sobre la imagen tal como llega), luego
      // se endereza.
      if mirrored {
        if rotation == 0 {
          return vImageHorizontalReflect_ARGB8888(&src, &dst, vImage_Flags(kvImageNoFlags))
        }
        var tmp = scratchBuffer(width: width, height: height)
        let e = vImageHorizontalReflect_ARGB8888(&src, &tmp, vImage_Flags(kvImageNoFlags))
        if e != kvImageNoError { return e }
        src = tmp
      }
      if rotation == 0 {
        return vImageCopyBuffer(&src, &dst, 4, vImage_Flags(kvImageNoFlags))
      }
      // `rotation` es el giro horario que endereza la imagen.
      let quarters: UInt8 =
        rotation == 90 ? UInt8(kRotate90DegreesClockwise)
        : rotation == 180 ? UInt8(kRotate180DegreesClockwise)
        : UInt8(kRotate270DegreesClockwise)
      var black: [UInt8] = [0, 0, 0, 255]
      return vImageRotate90_ARGB8888(&src, &dst, quarters, &black, vImage_Flags(kvImageNoFlags))
    }
    guard err == kvImageNoError else { throw PoseError("vImage \(err)") }

    // detect(videoFrame:) exige timestamps estrictamente crecientes.
    var ts = Int(ProcessInfo.processInfo.systemUptime * 1000)
    if ts <= lastTimestampMs { ts = lastTimestampMs + 1 }
    lastTimestampMs = ts

    let image = try MPImage(pixelBuffer: pb)
    let res = try lm.detect(videoFrame: image, timestampInMilliseconds: ts)
    guard let pose = res.landmarks.first else { return [] }
    return PoseChannel.flatten(pose)
  }

  private func reusablePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
    if let pb = pixelBuffer, CVPixelBufferGetWidth(pb) == width,
      CVPixelBufferGetHeight(pb) == height
    {
      return pb
    }
    var pb: CVPixelBuffer?
    let attrs = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary
    CVPixelBufferCreate(
      kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs, &pb)
    pixelBuffer = pb
    return pb
  }

  private func scratchBuffer(width: Int, height: Int) -> vImage_Buffer {
    let rowBytes = width * 4
    let size = rowBytes * height
    if scratchSize < size {
      scratch?.deallocate()
      scratch = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
      scratchSize = size
    }
    return vImage_Buffer(
      data: scratch, height: vImagePixelCount(height), width: vImagePixelCount(width),
      rowBytes: rowBytes)
  }

  private static func flatten(_ pose: [NormalizedLandmark]) -> [Double] {
    var out = [Double]()
    out.reserveCapacity(pose.count * 4)
    for l in pose {
      out.append(Double(l.x))
      out.append(Double(l.y))
      out.append(Double(l.z))
      out.append(l.visibility?.doubleValue ?? 0)
    }
    return out
  }

  // MARK: - processVideo

  /// Procesa un archivo de video con MediaPipe en modo VIDEO. Devuelve, por
  /// fotograma con cuerpo, un arreglo plano [x, y, z, visibility] x 33, y el
  /// aspecto (alto/ancho) de los fotogramas ya derechos.
  private func processVideo(_ path: String) throws -> [String: Any] {
    let lm = try PoseChannel.makeLandmarker()
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    guard let track = asset.tracks(withMediaType: .video).first else {
      throw PoseError("el video no tiene pista de imagen")
    }
    let reader = try AVAssetReader(asset: asset)
    // La composición aplica `preferredTransform`: los fotogramas salen derechos,
    // igual que MediaMetadataRetriever en Android.
    let output = AVAssetReaderVideoCompositionOutput(
      videoTracks: [track],
      videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    output.videoComposition = AVVideoComposition(propertiesOf: asset)
    output.alwaysCopiesSampleData = false
    reader.add(output)
    guard reader.startReading() else {
      throw PoseError("no se pudo leer el video: \(String(describing: reader.error))")
    }
    defer { reader.cancelReading() }

    var frames = [[Double]]()
    var aspect = 0.0
    let intervalMs = 33  // ~30 fps (igual que Android)
    var nextMs = 0
    var lastTs = -1
    while let sample = output.copyNextSampleBuffer() {
      guard let pb = CMSampleBufferGetImageBuffer(sample) else { continue }
      let ms = Int(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)) * 1000)
      if ms < nextMs { continue }
      while nextMs <= ms { nextMs += intervalMs }
      let ts = max(ms, lastTs + 1)
      lastTs = ts
      autoreleasepool {
        if aspect == 0 {
          let w = CVPixelBufferGetWidth(pb)
          if w > 0 { aspect = Double(CVPixelBufferGetHeight(pb)) / Double(w) }
        }
        // Fotograma ilegible: se omite.
        guard let image = try? MPImage(pixelBuffer: pb),
          let res = try? lm.detect(videoFrame: image, timestampInMilliseconds: ts),
          let pose = res.landmarks.first
        else { return }
        frames.append(PoseChannel.flatten(pose))
      }
    }
    return ["aspect": aspect, "frames": frames]
  }

  // MARK: - videoThumbnail

  /// Frame del centro del video como JPEG, para usar de portada en el catálogo.
  private func videoThumbnail(_ path: String) -> Data? {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let mid = CMTimeMultiplyByRatio(asset.duration, multiplier: 1, divisor: 2)
    guard let cg = try? generator.copyCGImage(at: mid, actualTime: nil) else { return nil }
    return UIImage(cgImage: cg).jpegData(compressionQuality: 0.8)
  }
}

private struct PoseError: LocalizedError, CustomStringConvertible {
  let description: String
  init(_ message: String) { description = message }
  var errorDescription: String? { description }
}
