package com.example.simplek

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.content.ClipData
import androidx.core.content.FileProvider
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "simplek/document_share")
            .setMethodCallHandler { call, result ->
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
                    if (call.argument<String>("target") == "whatsapp") {
                        val pkg = listOf("com.whatsapp", "com.whatsapp.w4b").firstOrNull {
                            packageManager.getLaunchIntentForPackage(it) != null
                        } ?: throw IllegalStateException("Please install WhatsApp or WhatsApp Business.")
                        intent.setPackage(pkg)
                        intent.putExtra("jid", call.argument<String>("recipient") + "@s.whatsapp.net")
                        startActivity(intent)
                    } else {
                        intent.putExtra(Intent.EXTRA_EMAIL, arrayOf(call.argument<String>("recipient") ?: ""))
                        startActivity(Intent.createChooser(intent, "Email invoice PDF"))
                    }
                    result.success(null)
                } catch (e: Exception) {
                    result.error("SHARE_FAILED", e.message, null)
                }
            }
    }
}
