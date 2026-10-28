// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

package com.filetransfer.file_transfer

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import java.io.File
import java.io.IOException

/**
 * Mueve un archivo recibido (en la caché de la app) a Descargas/Trasvo,
 * donde el usuario lo encuentra con cualquier explorador o galería.
 */
object DownloadsSaver {
    private const val ROOT = "Trasvo"

    /** Devuelve la ruta visible para el usuario (p. ej. `Download/Trasvo/foto.jpg`). */
    fun save(context: Context, source: File, subfolder: String): String {
        require(source.isFile) { "No existe: ${source.path}" }
        val folders = listOf(ROOT, subfolder).filter { it.isNotEmpty() }.joinToString("/")
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveWithMediaStore(context, source, "${Environment.DIRECTORY_DOWNLOADS}/$folders")
        } else {
            saveLegacy(source, folders)
        }
    }

    private fun saveWithMediaStore(context: Context, source: File, relativePath: String): String {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, source.name)
            put(MediaStore.Downloads.MIME_TYPE, mimeType(source.name))
            put(MediaStore.Downloads.RELATIVE_PATH, relativePath)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("No se pudo crear el archivo en Descargas")
        try {
            val output = resolver.openOutputStream(uri) ?: throw IOException("Sin acceso a Descargas")
            output.use { out -> source.inputStream().use { it.copyTo(out) } }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        source.delete()

        // MediaStore renombra si ya existe ("foto (1).jpg"): leemos el nombre final.
        val finalName = resolver.query(uri, arrayOf(MediaStore.Downloads.DISPLAY_NAME), null, null, null)
            ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
            ?: source.name
        return "$relativePath/$finalName"
    }

    @Suppress("DEPRECATION")
    private fun saveLegacy(source: File, folders: String): String {
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), folders)
        if (!dir.isDirectory && !dir.mkdirs()) throw IOException("No se pudo crear ${dir.path}")
        val stem = source.nameWithoutExtension
        val ext = source.extension.let { if (it.isEmpty()) "" else ".$it" }
        var dest = File(dir, source.name)
        var n = 1
        while (dest.exists()) {
            dest = File(dir, "$stem ($n)$ext")
            n++
        }
        source.copyTo(dest)
        source.delete()
        return dest.absolutePath
    }

    private fun mimeType(name: String): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
    }
}
