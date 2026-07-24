package com.gangchat.client

import android.os.Build
import android.content.Intent
import android.view.Surface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var updateInstaller: AndroidUpdateInstaller? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "gang_chat/display_orientation",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDisplayRotation" -> result.success(currentDisplayRotation())
                else -> result.notImplemented()
            }
        }
        updateInstaller = AndroidUpdateInstaller(this).also { installer ->
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                AndroidUpdateInstaller.channelName,
            ).setMethodCallHandler(installer::handleMethodCall)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        updateInstaller?.onActivityResult(requestCode)
    }

    override fun onResume() {
        super.onResume()
        updateInstaller?.onResume()
    }

    @Suppress("DEPRECATION")
    private fun currentDisplayRotation(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display?.rotation ?: Surface.ROTATION_0
        } else {
            windowManager.defaultDisplay.rotation
        }
    }
}
