package zip.atri.sparxie

import android.database.Cursor
import android.database.MatrixCursor
import android.provider.DocumentsContract
import android.provider.DocumentsProvider
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import java.io.File

class SparxieDocumentsProvider : DocumentsProvider() {
    private lateinit var root: File
    private val rootId = "sparxie"

    override fun onCreate(): Boolean {
        root = File(requireNotNull(context).filesDir, "core/configs").apply { mkdirs() }
        return true
    }

    override fun queryRoots(projection: Array<out String>?): Cursor = MatrixCursor(ROOT_COLUMNS).apply {
        newRow().apply {
            add(DocumentsContract.Root.COLUMN_ROOT_ID, rootId)
            add(DocumentsContract.Root.COLUMN_DOCUMENT_ID, rootId)
            add(DocumentsContract.Root.COLUMN_ICON, R.mipmap.ic_launcher)
            add(DocumentsContract.Root.COLUMN_TITLE, "Sparxie")
            add(
                DocumentsContract.Root.COLUMN_FLAGS,
                DocumentsContract.Root.FLAG_LOCAL_ONLY or
                    DocumentsContract.Root.FLAG_SUPPORTS_IS_CHILD or
                    DocumentsContract.Root.FLAG_SUPPORTS_CREATE,
            )
            add(DocumentsContract.Root.COLUMN_MIME_TYPES, DocumentsContract.Document.MIME_TYPE_DIR)
        }
    }

    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor =
        MatrixCursor(DOC_COLUMNS).also { addDocument(it, fileFor(documentId)) }

    override fun queryChildDocuments(parentDocumentId: String, projection: Array<out String>?, sortOrder: String?): Cursor =
        MatrixCursor(DOC_COLUMNS).apply {
            if (parentDocumentId == rootId) {
                root.listFiles()
                    ?.filter { it.isFile && (it.extension.equals("yaml", true) || it.extension.equals("yml", true)) }
                    ?.sortedBy { it.name.lowercase() }
                    ?.forEach { addDocument(this, it) }
            }
        }

    override fun openDocument(documentId: String, mode: String, signal: CancellationSignal?): ParcelFileDescriptor =
        fileFor(documentId).let { file ->
            require(file != root) { "无法打开配置目录" }
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.parseMode(mode))
        }

    override fun deleteDocument(documentId: String) {
        val file = fileFor(documentId)
        require(file != root) { "无法删除配置目录" }
        if (!file.delete()) throw IllegalStateException("删除配置失败")
        notifyDocument(documentId)
    }

    override fun renameDocument(documentId: String, displayName: String): String {
        val safeName = displayName.trim().replace(Regex("[\\\\/:*?\"<>|]"), "_")
        require(safeName.isNotEmpty()) { "文件名不能为空" }
        val source = fileFor(documentId)
        require(source != root) { "无法重命名配置目录" }
        val target = File(root, safeName).canonicalFile
        check(target.parentFile == root.canonicalFile) { "非法文档路径" }
        require(!isInternalName(target.name)) { "不允许操作内部文件" }
        require(!target.exists()) { "文件已存在" }
        if (!source.renameTo(target)) throw IllegalStateException("重命名配置失败")
        notifyDocument(documentId)
        notifyDocument("$rootId/${target.name}")
        return "$rootId/${target.name}"
    }

    override fun isChildDocument(parentDocumentId: String, documentId: String): Boolean {
        return parentDocumentId == rootId && documentId != rootId &&
            fileFor(documentId).parentFile == root.canonicalFile
    }

    override fun createDocument(documentId: String, mimeType: String, displayName: String): String {
        require(documentId == rootId) { "只能在配置目录中创建文件" }
        val safeName = displayName.trim().replace(Regex("[\\\\/:*?\"<>|]"), "_")
        require(safeName.isNotEmpty()) { "文件名不能为空" }
        val file = File(root, safeName).canonicalFile
        check(file.parentFile == root.canonicalFile) { "非法文档路径" }
        require(!isInternalName(file.name)) { "不允许操作内部文件" }
        if (!file.createNewFile()) throw IllegalStateException("文件已存在")
        notifyDocument("$rootId/${file.name}")
        return "$rootId/${file.name}"
    }

    private fun notifyDocument(documentId: String) {
        val uri = DocumentsContract.buildDocumentUri(
            "${requireNotNull(context).packageName}.documents", documentId,
        )
        requireNotNull(context).contentResolver.notifyChange(uri, null)
    }

    private fun fileFor(id: String): File = if (id == rootId) root else File(root, id.removePrefix("$rootId/")).canonicalFile.also {
        check(it.parentFile == root.canonicalFile) { "非法文档路径" }
        require(!isInternalName(it.name)) { "不允许访问内部文件" }
    }

    private fun isInternalName(name: String): Boolean =
        name == "index.json" || name.startsWith(".")

    private fun addDocument(cursor: MatrixCursor, file: File) {
        val id = if (file == root) rootId else "$rootId/${file.name}"
        cursor.newRow().apply {
            add(DocumentsContract.Document.COLUMN_DOCUMENT_ID, id)
            add(DocumentsContract.Document.COLUMN_DISPLAY_NAME, file.name)
            add(DocumentsContract.Document.COLUMN_SIZE, if (file.isFile) file.length() else 0)
            add(DocumentsContract.Document.COLUMN_MIME_TYPE, if (file.isDirectory) DocumentsContract.Document.MIME_TYPE_DIR else "text/yaml")
            add(
                DocumentsContract.Document.COLUMN_FLAGS,
                if (file.isDirectory) {
                    DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE or
                        DocumentsContract.Document.FLAG_SUPPORTS_WRITE or
                        DocumentsContract.Document.FLAG_SUPPORTS_RENAME or
                        DocumentsContract.Document.FLAG_SUPPORTS_DELETE
                } else {
                    DocumentsContract.Document.FLAG_SUPPORTS_WRITE or
                        DocumentsContract.Document.FLAG_SUPPORTS_RENAME or
                        DocumentsContract.Document.FLAG_SUPPORTS_DELETE
                },
            )
            add(DocumentsContract.Document.COLUMN_LAST_MODIFIED, file.lastModified())
        }
    }

    companion object {
        private val ROOT_COLUMNS = arrayOf(DocumentsContract.Root.COLUMN_ROOT_ID, DocumentsContract.Root.COLUMN_DOCUMENT_ID, DocumentsContract.Root.COLUMN_TITLE, DocumentsContract.Root.COLUMN_FLAGS, DocumentsContract.Root.COLUMN_MIME_TYPES, DocumentsContract.Root.COLUMN_ICON)
        private val DOC_COLUMNS = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_SIZE, DocumentsContract.Document.COLUMN_MIME_TYPE, DocumentsContract.Document.COLUMN_FLAGS, DocumentsContract.Document.COLUMN_LAST_MODIFIED)
    }
}
