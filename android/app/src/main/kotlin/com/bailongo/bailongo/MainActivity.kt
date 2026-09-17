package com.bailongo.bailongo

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.SystemClock
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Platform channel que envuelve MediaPipe Tasks Vision PoseLandmarker
 * (modelo pose_landmarker_lite.task, 33 landmarks BlazePose, doc 6.1).
 *
 * Modo VIDEO: cada fotograma entra como NV21 desde el plugin `camera` de
 * Flutter, se convierte a Bitmap vertical en un solo paso y se detecta en un
 * hilo dedicado, devolviendo un arreglo plano [x,y,z,visibility] x 33.
 *
 * Claves de rendimiento (RNF-04, >= 24 FPS):
 *  - La inferencia NO corre en el hilo principal: bloquearlo congelaba la
 *    preview de cámara, que la compone ese mismo hilo.
 *  - NV21 -> ARGB con rotación fusionada en un único recorrido, sobre buffers
 *    reutilizados. Antes se comprimía a JPEG y se volvía a decodificar, más una
 *    segunda copia del bitmap para rotarlo: tres pasadas y dos asignaciones
 *    grandes por fotograma.
 *  - RunningMode.VIDEO en vez de IMAGE: MediaPipe reutiliza el seguimiento
 *    entre fotogramas en lugar de relanzar el detector de persona en cada uno.
 *  - Se devuelve DoubleArray (llega a Dart como Float64List) en vez de una
 *    lista de 132 Double envueltos.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "bailongo/pose"
    private var landmarker: PoseLandmarker? = null

    /** Un solo hilo: MediaPipe en modo VIDEO exige fotogramas en orden. */
    private var poseExecutor: ExecutorService? = null

    /** Timestamp monotónico creciente exigido por `detectForVideo`. */
    private var lastTimestampMs = 0L

    // Buffers reutilizados entre fotogramas para no asignar ~1 MB por frame.
    private var argbBuffer: IntArray? = null
    private var reusableBitmap: Bitmap? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "init" -> {
                        try {
                            initLandmarker()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("INIT_FAILED", e.message, null)
                        }
                    }
                    "detect" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val width = call.argument<Int>("width")
                        val height = call.argument<Int>("height")
                        val rotation = call.argument<Int>("rotation") ?: 0
                        if (bytes == null || width == null || height == null) {
                            result.error("BAD_ARGS", "bytes/width/height requeridos", null)
                        } else {
                            // Fuera del hilo principal: si se bloquea, la preview
                            // de cámara se congela (RNF-04).
                            val executor = poseExecutor
                            if (executor == null) {
                                result.error("NOT_INITIALIZED", "landmarker no inicializado", null)
                            } else {
                                executor.execute {
                                    try {
                                        val out = detect(bytes, width, height, rotation)
                                        runOnUiThread { result.success(out) }
                                    } catch (e: Exception) {
                                        runOnUiThread {
                                            result.error("DETECT_FAILED", e.message, null)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    "processVideo" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("BAD_ARGS", "path requerido", null)
                        } else {
                            // Pesado: fuera del hilo principal, respuesta en UI.
                            Thread {
                                try {
                                    val frames = processVideo(path)
                                    runOnUiThread { result.success(frames) }
                                } catch (e: Exception) {
                                    runOnUiThread {
                                        result.error("VIDEO_FAILED", e.message, null)
                                    }
                                }
                            }.start()
                        }
                    }
                    "videoThumbnail" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("BAD_ARGS", "path requerido", null)
                        } else {
                            Thread {
                                try {
                                    val bytes = videoThumbnail(path)
                                    runOnUiThread { result.success(bytes) }
                                } catch (e: Exception) {
                                    runOnUiThread {
                                        result.error("THUMB_FAILED", e.message, null)
                                    }
                                }
                            }.start()
                        }
                    }
                    "close" -> {
                        closeLandmarker()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun initLandmarker() {
        if (poseExecutor == null) {
            poseExecutor = Executors.newSingleThreadExecutor()
        }
        if (landmarker != null) return
        val base = BaseOptions.builder()
            .setModelAssetPath("pose_landmarker_lite.task")
            .setDelegate(Delegate.CPU)
            .build()
        val options = PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(base)
            // VIDEO reutiliza el seguimiento entre fotogramas; IMAGE relanzaba
            // el detector de persona en cada uno.
            .setRunningMode(RunningMode.VIDEO)
            .setMinPoseDetectionConfidence(0.5f)
            .setMinPosePresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .setNumPoses(1)
            .build()
        landmarker = PoseLandmarker.createFromOptions(this, options)
        lastTimestampMs = 0L
    }

    private fun closeLandmarker() {
        poseExecutor?.shutdown()
        poseExecutor = null
        landmarker?.close()
        landmarker = null
        reusableBitmap?.recycle()
        reusableBitmap = null
        argbBuffer = null
        lastTimestampMs = 0L
    }

    override fun onDestroy() {
        closeLandmarker()
        super.onDestroy()
    }

    /**
     * Corre en [poseExecutor]. Devuelve [x,y,z,visibility] x 33, o un arreglo
     * vacío si no hay cuerpo. Las coordenadas son normalizadas 0..1 sobre la
     * imagen YA vertical.
     */
    private fun detect(nv21: ByteArray, width: Int, height: Int, rotation: Int): DoubleArray {
        val lm = landmarker ?: return EMPTY
        val upright = nv21ToUprightBitmap(nv21, width, height, rotation) ?: return EMPTY

        // detectForVideo exige timestamps estrictamente crecientes.
        var ts = SystemClock.uptimeMillis()
        if (ts <= lastTimestampMs) ts = lastTimestampMs + 1
        lastTimestampMs = ts

        val result = lm.detectForVideo(BitmapImageBuilder(upright).build(), ts)
        val poses = result.landmarks()
        if (poses.isEmpty()) return EMPTY

        val pose = poses[0]
        val out = DoubleArray(pose.size * 4)
        var i = 0
        for (l in pose) {
            out[i++] = l.x().toDouble()
            out[i++] = l.y().toDouble()
            out[i++] = l.z().toDouble()
            out[i++] = l.visibility().orElse(0f).toDouble()
        }
        return out
    }

    /**
     * Procesa un archivo de video con MediaPipe en modo VIDEO (porta
     * VideoProcessor.kt del prototipo). Devuelve, por fotograma con cuerpo, un
     * arreglo plano [x, y, z, visibility] x 33.
     */
    private fun processVideo(path: String): Map<String, Any> {
        val base = BaseOptions.builder()
            .setModelAssetPath("pose_landmarker_lite.task")
            .setDelegate(Delegate.CPU)
            .build()
        val options = PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(base)
            .setRunningMode(RunningMode.VIDEO)
            .setMinPoseDetectionConfidence(0.5f)
            .setMinPosePresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .setNumPoses(1)
            .build()
        val lm = PoseLandmarker.createFromOptions(this, options)
        val retriever = MediaMetadataRetriever()
        val frames = ArrayList<List<Double>>()
        // Alto/ancho de los fotogramas que ve MediaPipe: las coordenadas vienen
        // normalizadas por cada eje y Dart corrige el aspecto con esto.
        var aspect = 0.0
        try {
            retriever.setDataSource(path)
            val durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            val intervalMs = 33L // ~30 fps (igual que el prototipo)
            var ts = 0L
            while (ts < durationMs) {
                try {
                    val bmp = retriever.getFrameAtTime(
                        ts * 1000,
                        MediaMetadataRetriever.OPTION_CLOSEST,
                    )?.copy(Bitmap.Config.ARGB_8888, false)
                    if (bmp != null) {
                        if (aspect == 0.0 && bmp.width > 0) {
                            aspect = bmp.height.toDouble() / bmp.width
                        }
                        val res = lm.detectForVideo(BitmapImageBuilder(bmp).build(), ts)
                        if (res.landmarks().isNotEmpty()) {
                            val frame = ArrayList<Double>(33 * 4)
                            for (l in res.landmarks()[0]) {
                                frame.add(l.x().toDouble())
                                frame.add(l.y().toDouble())
                                frame.add(l.z().toDouble())
                                frame.add(l.visibility().orElse(0f).toDouble())
                            }
                            frames.add(frame)
                        }
                        bmp.recycle()
                    }
                } catch (_: Exception) {
                    // Fotograma ilegible: se omite.
                }
                ts += intervalMs
            }
        } finally {
            retriever.release()
            lm.close()
        }
        return mapOf("aspect" to aspect, "frames" to frames)
    }

    /// Frame del centro del video como JPEG, para usar de portada en el catálogo.
    private fun videoThumbnail(path: String): ByteArray? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            val bmp = retriever.getFrameAtTime(
                (durationMs / 2) * 1000,
                MediaMetadataRetriever.OPTION_CLOSEST,
            ) ?: return null
            val out = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.JPEG, 80, out)
            bmp.recycle()
            out.toByteArray()
        } catch (e: Exception) {
            null
        } finally {
            retriever.release()
        }
    }

    /**
     * NV21 -> Bitmap ARGB ya rotado a vertical, en un único recorrido y sobre
     * buffers reutilizados.
     *
     * [rotation] son los grados EN SENTIDO HORARIO que hay que girar la imagen
     * para dejarla derecha, la misma convención que usaba `Matrix.postRotate`.
     */
    private fun nv21ToUprightBitmap(
        nv21: ByteArray,
        width: Int,
        height: Int,
        rotation: Int,
    ): Bitmap? {
        if (nv21.size < width * height * 3 / 2) return null
        val swap = rotation == 90 || rotation == 270
        val dstW = if (swap) height else width
        val dstH = if (swap) width else height
        val size = dstW * dstH

        var argb = argbBuffer
        if (argb == null || argb.size != size) {
            argb = IntArray(size)
            argbBuffer = argb
        }
        yuv420spToArgb(nv21, width, height, rotation, argb, dstW)

        var bmp = reusableBitmap
        if (bmp == null || bmp.width != dstW || bmp.height != dstH) {
            bmp?.recycle()
            bmp = Bitmap.createBitmap(dstW, dstH, Bitmap.Config.ARGB_8888)
            reusableBitmap = bmp
        }
        bmp.setPixels(argb, 0, dstW, 0, 0, dstW, dstH)
        return bmp
    }

    /**
     * Conversión YUV420sp (NV21) a ARGB con la rotación aplicada al escribir,
     * en aritmética entera (coeficientes BT.601, los mismos que usa Android).
     */
    private fun yuv420spToArgb(
        yuv: ByteArray,
        width: Int,
        height: Int,
        rotation: Int,
        out: IntArray,
        dstW: Int,
    ) {
        val frameSize = width * height
        var yp = 0
        for (j in 0 until height) {
            var uvp = frameSize + (j shr 1) * width
            var u = 0
            var v = 0
            for (i in 0 until width) {
                var y = (0xff and yuv[yp].toInt()) - 16
                if (y < 0) y = 0
                if (i and 1 == 0) {
                    v = (0xff and yuv[uvp++].toInt()) - 128
                    u = (0xff and yuv[uvp++].toInt()) - 128
                }
                val y1192 = 1192 * y
                var r = y1192 + 1634 * v
                var g = y1192 - 833 * v - 400 * u
                var b = y1192 + 2066 * u
                if (r < 0) r = 0 else if (r > 262143) r = 262143
                if (g < 0) g = 0 else if (g > 262143) g = 262143
                if (b < 0) b = 0 else if (b > 262143) b = 262143

                // Destino según el giro horario pedido.
                val dst = when (rotation) {
                    90 -> i * dstW + (height - 1 - j)
                    180 -> (height - 1 - j) * dstW + (width - 1 - i)
                    270 -> (width - 1 - i) * dstW + j
                    else -> j * dstW + i
                }
                out[dst] = -0x1000000 or
                    ((r shl 6) and 0xff0000) or
                    ((g shr 2) and 0xff00) or
                    ((b shr 10) and 0xff)
                yp++
            }
        }
    }

    private companion object {
        val EMPTY = DoubleArray(0)
    }
}
