package com.gangchat.client

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class AndroidUpdateInstaller(private val activity: Activity) {
    private data class PendingInstall(
        val apk: File,
        val result: MethodChannel.Result,
    )

    private var pendingInstall: PendingInstall? = null
    private var waitingForInstallPermission = false

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "installApk") {
            result.notImplemented()
            return
        }
        if (pendingInstall != null) {
            result.error(
                "install_in_progress",
                "An Android update install is already pending.",
                null,
            )
            return
        }

        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error("invalid_apk", "The APK path is missing.", null)
            return
        }
        val apk = validateApk(path, result) ?: return

        if (needsInstallPermission()) {
            pendingInstall = PendingInstall(apk, result)
            waitingForInstallPermission = true
            try {
                activity.startActivityForResult(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${activity.packageName}"),
                    ),
                    installPermissionRequestCode,
                )
            } catch (_: ActivityNotFoundException) {
                clearPendingInstall()?.result?.error(
                    "installer_unavailable",
                    "The system install permission page is unavailable.",
                    null,
                )
            } catch (error: Exception) {
                clearPendingInstall()?.result?.error(
                    "installer_unavailable",
                    error.message,
                    null,
                )
            }
            return
        }

        launchInstaller(apk, result)
    }

    fun onActivityResult(requestCode: Int): Boolean {
        if (requestCode != installPermissionRequestCode) return false
        finishInstallPermissionRequest()
        return true
    }

    fun onResume() {
        if (!waitingForInstallPermission || pendingInstall == null) return
        finishInstallPermissionRequest()
    }

    private fun finishInstallPermissionRequest() {
        val pending = clearPendingInstall() ?: return
        if (needsInstallPermission()) {
            pending.result.error(
                "permission_denied",
                "Permission to install unknown apps was not granted.",
                null,
            )
            return
        }
        launchInstaller(pending.apk, pending.result)
    }

    private fun clearPendingInstall(): PendingInstall? {
        waitingForInstallPermission = false
        val pending = pendingInstall
        pendingInstall = null
        return pending
    }

    private fun needsInstallPermission(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !activity.packageManager.canRequestPackageInstalls()
    }

    private fun validateApk(
        path: String,
        result: MethodChannel.Result,
    ): File? {
        val apk = try {
            File(path).canonicalFile
        } catch (error: Exception) {
            result.error("invalid_apk", error.message, null)
            return null
        }
        val updateRoot = File(activity.cacheDir, updateDirectoryName).canonicalFile
        val allowedPrefix = updateRoot.path + File.separator
        if (!apk.path.startsWith(allowedPrefix) ||
            !apk.name.matches(apkFilenamePattern) ||
            !apk.isFile ||
            !apk.canRead() ||
            apk.length() <= 0
        ) {
            result.error(
                "invalid_apk",
                "The APK is outside the private update directory or unreadable.",
                null,
            )
            return null
        }

        val archiveInfo = packageArchiveInfo(apk)
        if (archiveInfo == null) {
            result.error("invalid_apk", "Android could not parse the APK.", null)
            return null
        }
        if (archiveInfo.packageName != activity.packageName) {
            result.error(
                "invalid_package",
                "The APK belongs to a different application.",
                null,
            )
            return null
        }

        val installedInfo = installedPackageInfo()
        val installedSigners = installedInfo?.let(::signerDigests).orEmpty()
        val archiveSigners = signerDigests(archiveInfo)
        if (installedSigners.isEmpty() ||
            archiveSigners.isEmpty() ||
            installedSigners.intersect(archiveSigners).isEmpty()
        ) {
            result.error(
                "signature_mismatch",
                "The APK signing certificate does not match this installation.",
                null,
            )
            return null
        }
        return apk
    }

    private fun launchInstaller(apk: File, result: MethodChannel.Result) {
        try {
            val uri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.fileprovider",
                apk,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, apkMimeType)
                clipData = ClipData.newRawUri("", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivity(intent)
            result.success(null)
        } catch (_: ActivityNotFoundException) {
            result.error(
                "installer_unavailable",
                "No Android package installer is available.",
                null,
            )
        } catch (error: Exception) {
            result.error("invalid_apk", error.message, null)
        }
    }

    @Suppress("DEPRECATION")
    private fun packageArchiveInfo(apk: File): PackageInfo? {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        return activity.packageManager.getPackageArchiveInfo(apk.path, flags)
    }

    @Suppress("DEPRECATION")
    private fun installedPackageInfo(): PackageInfo? {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        return try {
            activity.packageManager.getPackageInfo(activity.packageName, flags)
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
    }

    @Suppress("DEPRECATION")
    private fun signerDigests(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = info.signingInfo ?: return emptySet()
            if (signingInfo.hasMultipleSigners()) {
                signingInfo.apkContentsSigners
            } else {
                signingInfo.signingCertificateHistory
            }
        } else {
            info.signatures
        }
        return signatures
            ?.map { signature ->
                MessageDigest
                    .getInstance("SHA-256")
                    .digest(signature.toByteArray())
                    .joinToString("") { byte -> "%02x".format(byte) }
            }
            ?.toSet()
            .orEmpty()
    }

    companion object {
        const val channelName = "gang_chat/app_update"
        private const val installPermissionRequestCode = 4107
        private const val updateDirectoryName = "release-updates"
        private const val apkMimeType = "application/vnd.android.package-archive"
        private val apkFilenamePattern =
            Regex("^GangChat_v\\d+\\.\\d+\\.\\d+\\.apk$", RegexOption.IGNORE_CASE)
    }
}
