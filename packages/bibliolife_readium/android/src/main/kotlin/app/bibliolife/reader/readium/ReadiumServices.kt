package app.bibliolife.reader.readium

import android.content.Context
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.parser.DefaultPublicationParser

class ReadiumServices(context: Context) {
    private val appContext = context.applicationContext
    private val httpClient = DefaultHttpClient()
    val assetRetriever = AssetRetriever(appContext.contentResolver, httpClient)
    val publicationOpener = PublicationOpener(
        DefaultPublicationParser(appContext, httpClient, assetRetriever, null)
    )
}
