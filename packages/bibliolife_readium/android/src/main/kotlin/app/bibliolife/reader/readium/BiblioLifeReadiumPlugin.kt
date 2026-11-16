package app.bibliolife.reader.readium

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class BiblioLifeReadiumPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private val pluginScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var tocExtractor: ReadiumTocExtractor? = null
    private val activityDependencyProvider = ReadiumActivityDependencyProvider()
    private var platformViewFactory: ReadiumPlatformViewFactory? = null
    private var bridgeTransportFactory: ReadiumFlutterBridgeTransportFactory? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "app.bibliolife.reader/readium")
        channel.setMethodCallHandler(this)
        val transportFactory = ReadiumFlutterBridgeTransportFactory(binding.binaryMessenger)
        bridgeTransportFactory = transportFactory
        platformViewFactory = ReadiumPlatformViewFactory(activityDependencyProvider, transportFactory).also { factory ->
            binding.platformViewRegistry.registerViewFactory(
                ReadiumPlatformViewContract.VIEW_TYPE,
                factory,
            )
        }
        tocExtractor = ReadiumTocExtractor(
            PublicationLoader(ReadiumServices(binding.applicationContext)),
        )
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "extractTableOfContents") {
            val filePath = call.argument<String>("filePath")
            val extractor = tocExtractor
            if (filePath.isNullOrBlank() || extractor == null) {
                result.success(mapOf("status" to "failed", "failure" to "invalid_path"))
                return
            }
            pluginScope.launch {
                result.success(
                    withContext(Dispatchers.IO) { extractor.extract(File(filePath)) },
                )
            }
            return
        }
        result.notImplemented()
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityDependencyProvider.attach(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityDependencyProvider.detachForConfigChanges()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityDependencyProvider.attach(binding.activity)
    }

    override fun onDetachedFromActivity() {
        activityDependencyProvider.detach()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        activityDependencyProvider.detach()
        bridgeTransportFactory?.detach()
        bridgeTransportFactory = null
        platformViewFactory = null
        pluginScope.cancel()
        tocExtractor = null
        channel.setMethodCallHandler(null)
    }
}
