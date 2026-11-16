package app.bibliolife.reader.readium

import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import java.io.File
import kotlinx.coroutines.CancellationException
import org.readium.r2.shared.publication.Publication

class PublicationLoader(private val services: ReadiumServices) {
    sealed class Result {
        data class Success(val publication: Publication) : Result()
        data class Failure(val code: String, val diagnostic: Map<String, Any?>? = null) : Result()
    }

    suspend fun open(
        file: File,
        onStage: ((Map<String, Any?>) -> Unit)? = null,
    ): Result {
        var stage = "file_access"
        var component = "android_file"
        fun emit(result: String, facts: Map<String, Any?> = emptyMap()) =
            onStage?.invoke(ReadiumOpenDiagnostics.stage(stage, result, component, facts))
        fun failure(code: String, facts: () -> Map<String, Any?> = { emptyMap() }) =
            Result.Failure(code, onStage?.let {
                ReadiumOpenDiagnostics.stage(stage, "failed", component, facts() + ("errorCode" to code))
            })

        emit("started", mapOf("fileAccessChecked" to true))
        try {
            if (!file.isFile) return failure("file_not_found") {
                // isFile alone conflates a missing path, a directory and stat permission failures.
                try {
                    Os.stat(file.path)
                    mapOf("fileExists" to true, "pathIsRegularFile" to false, "message" to "Path is not a regular file")
                } catch (error: ErrnoException) {
                    ReadiumOpenDiagnostics.exception(error) + when (error.errno) {
                        OsConstants.ENOENT, OsConstants.ENOTDIR -> mapOf("fileExists" to false)
                        OsConstants.EACCES, OsConstants.EPERM -> mapOf("readable" to false)
                        else -> emptyMap()
                    }
                } catch (error: Exception) {
                    ReadiumOpenDiagnostics.exception(error)
                }
            }
            if (onStage != null) {
                val attributes = runCatching {
                    mapOf("fileSizeBytes" to Os.stat(file.path).st_size, "readable" to file.canRead())
                }.getOrDefault(emptyMap())
                emit("success", mapOf("fileExists" to true, "pathIsRegularFile" to true) + attributes)
            }
            stage = "asset_retrieval"
            component = "readium_asset_retriever"
            emit("started")
            if (!file.extension.equals("epub", true)) return failure("unsupported_format")
            val assetResult = services.assetRetriever.retrieve(file)
            val asset = assetResult.getOrNull() ?: return failure("asset_retrieval_failed") {
                ReadiumOpenDiagnostics.readiumFailure(assetResult.failureOrNull())
            }
            emit("success", mapOf("readable" to true))

            stage = "publication_open"
            component = "readium_publication_opener"
            emit("started")
            val publicationResult = services.publicationOpener.open(
                asset = asset,
                allowUserInteraction = false,
            )
            val publication = publicationResult.getOrNull()
                ?: run {
                    // PublicationOpener does not take ownership of a failed asset.
                    asset.close()
                    return failure("invalid_publication") {
                        ReadiumOpenDiagnostics.readiumFailure(publicationResult.failureOrNull())
                    }
                }
            emit("success")
            return Result.Success(publication)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            if (onStage != null) {
                emit("failed", ReadiumOpenDiagnostics.exception(error) + ("errorCode" to "${stage}_exception"))
            }
            throw error
        }
    }
}
