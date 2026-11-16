package com.example.simplek

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.content.ClipData
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "simplek/document_share")
            .setMethodCallHandler { call, result ->
                if (call.method == "openChat") {
                    try {
                        val uri = Uri.parse(call.argument<String>("url") ?: "")
                        require(uri.scheme == "https" && uri.host == "wa.me") { "Invalid WhatsApp link" }
                        val pkg = listOf("com.whatsapp", "com.whatsapp.w4b").firstOrNull {
                            packageManager.getLaunchIntentForPackage(it) != null
                        } ?: throw IllegalStateException("Please install WhatsApp or WhatsApp Business.")
                        startActivity(Intent(Intent.ACTION_VIEW, uri).setPackage(pkg))
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("CHAT_FAILED", e.message, null)
                    }
                    return@setMethodCallHandler
                }
                if (call.method != "share") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val folder = File(cacheDir, "invoice_shares").apply { mkdirs() }
                    val name = (call.argument<String>("filename") ?: "invoice.pdf")
                        .replace(Regex("[^A-Za-z0-9._-]"), "_")
                    val file = File(folder, name)
                    file.writeBytes(call.argument<ByteArray>("bytes")!!)
                    val uri = FileProvider.getUriForFile(this, "$packageName.documents", file)
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "application/pdf"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        putExtra(Intent.EXTRA_TEXT, call.argument<String>("body"))
                        putExtra(Intent.EXTRA_SUBJECT, call.argument<String>("subject"))
                        clipData = ClipData.newRawUri("Invoice PDF", uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    val target = call.argument<String>("target")
                    if (target == "whatsapp" || target == "whatsapp_picker") {
                        val pkg = listOf("com.whatsapp", "com.whatsapp.w4b").firstOrNull {
                            packageManager.getLaunchIntentForPackage(it) != null
                        } ?: throw IllegalStateException("Please install WhatsApp or WhatsApp Business.")
                        intent.setPackage(pkg)
                        if (target == "whatsapp") {
                            val recipient = call.argument<String>("recipient") ?: ""
                            require(recipient.matches(Regex("[0-9]{8,15}"))) { "Invalid WhatsApp number" }
                            // Best-effort recipient hint. WhatsApp versions may ignore it
                            // and show their contact picker; never assume delivery.
                            intent.putExtra("jid", "$recipient@s.whatsapp.net")
                        }
                        startActivity(intent)
                    } else if (call.argument<String>("target") == "email") {
                        intent.putExtra(Intent.EXTRA_EMAIL, arrayOf(call.argument<String>("recipient") ?: ""))
                        startActivity(Intent.createChooser(intent, "Email invoice PDF"))
                    } else {
                        startActivity(Intent.createChooser(intent, "Share invoice PDF"))
                    }
                    result.success(null)
                } catch (e: Exception) {
                    result.error("SHARE_FAILED", e.message, null)
                }
            }
    }
}
