package com.bailongo.bailongo

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Platform channel que envuelve MediaPipe Tasks Vision PoseLandmarker
 * (modelo pose_landmarker_lite.task, 33 landmarks BlazePose, doc 6.1).
 *
 * Modo IMAGE: cada fotograma entra como NV21 desde el plugin `camera` de
 * Flutter, se convierte a Bitmap (rotado a vertical) y se detecta de forma
 * síncrona, devolviendo un arreglo plano [x,y,z,visibility] x 33.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "bailongo/pose"
    private var landmarker: PoseLandmarker? = null

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
                        try {
                            val bytes = call.argument<ByteArray>("bytes")!!
                            val width = call.argument<Int>("width")!!
                            val height = call.argument<Int>("height")!!
                            val rotation = call.argument<Int>("rotation") ?: 0
                            result.success(detect(bytes, width, height, rotation))
                        } catch (e: Exception) {
                            result.error("DETECT_FAILED", e.message, null)
                        }
                    }
                    "close" -> {
                        landmarker?.close()
                        landmarker = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun initLandmarker() {
        if (landmarker != null) return
        val base = BaseOptions.builder()
            .setModelAssetPath("pose_landmarker_lite.task")
            .setDelegate(Delegate.CPU)
            .build()
        val options = PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(base)
            .setRunningMode(RunningMode.IMAGE)
            .setMinPoseDetectionConfidence(0.5f)
            .setMinPosePresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .setNumPoses(1)
            .build()
        landmarker = PoseLandmarker.createFromOptions(this, options)
    }

    private fun detect(nv21: ByteArray, width: Int, height: Int, rotation: Int): List<Double> {
        val lm = landmarker ?: return emptyList()
        val bitmap = nv21ToBitmap(nv21, width, height) ?: return emptyList()
        val upright = if (rotation != 0) rotateBitmap(bitmap, rotation) else bitmap

        val mpImage = BitmapImageBuilder(upright).build()
        val result = lm.detect(mpImage)

        val out = ArrayList<Double>(33 * 4)
        if (result.landmarks().isNotEmpty()) {
            for (l in result.landmarks()[0]) {
                out.add(l.x().toDouble())
                out.add(l.y().toDouble())
                out.add(l.z().toDouble())
                out.add(l.visibility().orElse(0f).toDouble())
            }
        }
        return out
    }

    private fun nv21ToBitmap(nv21: ByteArray, width: Int, height: Int): Bitmap? {
        return try {
            val yuv = YuvImage(nv21, ImageFormat.NV21, width, height, null)
            val out = ByteArrayOutputStream()
            yuv.compressToJpeg(Rect(0, 0, width, height), 90, out)
            val jpeg = out.toByteArray()
            BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)
        } catch (e: Exception) {
            null
        }
    }

    private fun rotateBitmap(src: Bitmap, degrees: Int): Bitmap {
        val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
        return Bitmap.createBitmap(src, 0, 0, src.width, src.height, matrix, true)
    }
}
