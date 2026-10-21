package it.lamialibreria.la_mia_libreria

import android.content.ContentUris
import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

private const val BACKUP_CHANNEL = "it.lamialibreria.la_mia_libreria/backups"
private const val BACKUP_FOLDER = "LaMiaLibreria"

class MainActivity : FlutterActivity() {
    private val backupExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKUP_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveBackup" && call.method != "listBackups") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                backupExecutor.execute {
                    try {
                        val response = when (call.method) {
                            "saveBackup" -> {
                                val path = call.argument<String>("path")
                                    ?: throw IllegalArgumentException("Missing backup path")
                                val name = call.argument<String>("name")
                                    ?: throw IllegalArgumentException("Missing backup name")
                                val automatic = call.argument<Boolean>("automatic") ?: false
                                saveBackup(File(path), name, automatic)
                                name
                            }
                            "listBackups" -> listBackups()
                            else -> error("Unsupported backup action")
                        }
                        mainHandler.post { result.success(response) }
                    } catch (error: Exception) {
                        mainHandler.post {
                            result.error("BACKUP_FAILED", error.message, null)
                        }
                    }
                }
            }
    }

    private fun saveBackup(source: File, name: String, automatic: Boolean) {
        check(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            "Salvare direttamente in Download richiede Android 10 o successivo."
        }
        check(source.isFile) { "Il file temporaneo del backup non esiste." }

        val resolver = contentResolver
        val collection = MediaStore.Downloads.getContentUri(
            MediaStore.VOLUME_EXTERNAL_PRIMARY
        )
        val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/$BACKUP_FOLDER/"
        val temporaryName = ".$name-${System.currentTimeMillis()}.pending"

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, temporaryName)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values)
            ?: error("Android non ha potuto creare il backup in Download.")

        try {
            resolver.openOutputStream(uri, "w")?.use { output ->
                source.inputStream().use { input -> input.copyTo(output) }
            } ?: error("Android non ha potuto scrivere il backup.")
            val ready = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            }
            resolver.update(uri, ready, null, null)
            deleteBackup(name, uri)
            if (automatic) pruneAutomaticBackups()
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    private fun listBackups(): List<Map<String, Any>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return emptyList()
        val collection = MediaStore.Downloads.getContentUri(
            MediaStore.VOLUME_EXTERNAL_PRIMARY
        )
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.RELATIVE_PATH
        )
        val backups = mutableListOf<Map<String, Any>>()
        contentResolver.query(collection, projection, null, null, null)?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val modifiedColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
            val pathColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.RELATIVE_PATH)
            while (cursor.moveToNext()) {
                val name = cursor.getString(nameColumn) ?: continue
                val path = cursor.getString(pathColumn) ?: continue
                if (!path.endsWith("$BACKUP_FOLDER/")) continue
                backups.add(
                    mapOf(
                        "id" to cursor.getLong(idColumn),
                        "name" to name,
                        "modified" to cursor.getLong(modifiedColumn)
                    )
                )
            }
        }
        return backups.sortedByDescending { it["modified"] as Long }
    }

    private fun deleteBackup(name: String, keepUri: Uri? = null) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val collection = MediaStore.Downloads.getContentUri(
            MediaStore.VOLUME_EXTERNAL_PRIMARY
        )
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        val selection = "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND " +
            "${MediaStore.MediaColumns.RELATIVE_PATH} = ?"
        val args = arrayOf(
            name,
            "${Environment.DIRECTORY_DOWNLOADS}/$BACKUP_FOLDER/"
        )
        contentResolver.query(
            collection,
            projection,
            selection,
            args,
            null
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            while (cursor.moveToNext()) {
                val id = cursor.getLong(idColumn)
                val uri = ContentUris.withAppendedId(collection, id)
                if (uri == keepUri) continue
                contentResolver.delete(
                    uri,
                    null,
                    null
                )
            }
        }
    }

    private fun pruneAutomaticBackups() {
        val automatic = listBackups()
            .filter { (it["name"] as String).startsWith("LaMiaLibreria-Auto-") }
            .sortedByDescending { it["name"] as String }
        automatic.drop(7).forEach { deleteBackup(it["name"] as String) }
    }

    override fun onDestroy() {
        backupExecutor.shutdown()
        super.onDestroy()
    }
}
