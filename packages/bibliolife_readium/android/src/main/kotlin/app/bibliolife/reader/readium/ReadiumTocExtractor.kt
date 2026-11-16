package app.bibliolife.reader.readium

import java.io.File
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Publication
import org.json.JSONObject

internal object TocPayloadBounds {
    const val MAX_DEPTH = 12
    const val MAX_ENTRIES = 2_000
    const val MAX_TITLE_LENGTH = 512
    const val MAX_PAYLOAD_BYTES = 1_000_000
}

internal class ReadiumTocExtractor(private val loader: PublicationLoader) {
    suspend fun extract(file: File): Map<String, Any?> {
        val opened = loader.open(file)
        if (opened is PublicationLoader.Result.Failure) {
            return mapOf("status" to "failed", "failure" to opened.code)
        }
        val publication = (opened as PublicationLoader.Result.Success).publication
        return try {
            val entries = convert(publication, publication.tableOfContents, 0, State())
            if (entries.isEmpty()) return mapOf("status" to "empty")
            val result = mapOf("status" to "success", "entries" to entries)
            if (JSONObject(result).toString().toByteArray(Charsets.UTF_8).size >
                TocPayloadBounds.MAX_PAYLOAD_BYTES
            ) mapOf("status" to "failed", "failure" to "payload_too_large") else result
        } catch (error: Throwable) {
            android.util.Log.w(
                "BiblioLifeReadium",
                "TOC_EXTRACTION_FAILED type=${error.javaClass.simpleName.take(64)}",
            )
            mapOf("status" to "failed", "failure" to "extraction_failed")
        } finally {
            publication.close()
        }
    }

    private fun convert(
        publication: Publication,
        links: List<Link>,
        depth: Int,
        state: State,
    ): List<Map<String, Any?>> {
        if (depth >= TocPayloadBounds.MAX_DEPTH || state.count >= TocPayloadBounds.MAX_ENTRIES) return emptyList()
        val output = mutableListOf<Map<String, Any?>>()
        for (link in links) {
            if (state.count >= TocPayloadBounds.MAX_ENTRIES) break
            val children = convert(publication, link.children, depth + 1, state)
            val title = link.title?.replace(Regex("\\s+"), " ")?.trim()
                ?.take(TocPayloadBounds.MAX_TITLE_LENGTH).orEmpty()
            val locator = publication.locatorFromLink(link)
            val locatorJson = locator?.let(TocLocatorPayload::serialize)
            val href = locatorJson?.let { json ->
                runCatching { org.readium.r2.shared.publication.Locator.fromJSON(JSONObject(json)) }
                    .getOrNull()?.href?.toString()?.trim()
            }.orEmpty()
            if (title.isEmpty() || href.isEmpty() || locatorJson == null) {
                output.addAll(children)
                continue
            }
            android.util.Log.d(
                "BiblioLifeReadium",
                "TOC_LOCATOR_SERIALIZED href=${href.take(160)} valid=true",
            )
            state.count += 1
            output += mapOf("title" to title, "locatorJson" to locatorJson, "children" to children)
        }
        return output
    }
    private class State(var count: Int = 0)
}
