package app.bibliolife.reader.readium

import org.json.JSONObject
import org.readium.r2.shared.publication.Locator

/** Validates the exact Readium JSON persisted for an extracted TOC target. */
internal object TocLocatorPayload {
    fun serialize(locator: Locator): String? {
        val json = locator.toJSON().toString()
        val decoded = runCatching { Locator.fromJSON(JSONObject(json)) }.getOrNull()
        return json.takeIf { decoded?.href?.toString()?.isNotBlank() == true }
    }
}
