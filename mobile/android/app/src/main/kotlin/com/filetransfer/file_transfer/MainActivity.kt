// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

package com.filetransfer.file_transfer

import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Puente con Dart (ver `lib/data/platform/device_storage.dart`). */
class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        val path = call.argument<String>("path")
                        val subfolder = call.argument<String>("subfolder") ?: ""
                        if (path == null) {
                            result.error("args", "path is required", null)
                            return@setMethodCallHandler
                        }
                        // Copiar puede tardar: fuera del hilo principal.
                        io.execute {
                            try {
                                val saved = DownloadsSaver.save(applicationContext, File(path), subfolder)
                                runOnUiThread { result.success(saved) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("io", e.message, null) }
                            }
                        }
                    }
                    "deviceName" -> result.success(deviceName())
                    else -> result.notImplemented()
                }
            }
    }

    private fun deviceName(): String {
        val userName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
            Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
        } else {
            null
        }
        return userName?.takeIf { it.isNotBlank() } ?: "${Build.MANUFACTURER} ${Build.MODEL}"
    }

    override fun onDestroy() {
        io.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "com.filetransfer/storage"
    }
}
