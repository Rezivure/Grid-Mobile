package app.mygrid.grid

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    // Must match AppLifecycleChannel.channelName on the Dart side.
    private val lifecycleChannel = "app.mygrid.grid/lifecycle"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            lifecycleChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Send the task to the background instead of finishing the
                // Activity. Finishing tears down the Flutter engine and stops
                // the location foreground service (GH #302); moveTaskToBack
                // keeps the service alive, matching Home-button behaviour.
                "moveTaskToBack" -> result.success(moveTaskToBack(true))
                else -> result.notImplemented()
            }
        }
    }
}
