package dev.orm.orm_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "orm_acceptance/config")
            .setMethodCallHandler { call, result ->
                if (call.method == "read") {
                    result.success(mapOf(
                        "filesPath" to filesDir.absolutePath,
                        "phase" to (intent.getStringExtra("orm_phase") ?: "upgrade"),
                        "api" to android.os.Build.VERSION.SDK_INT,
                        "pid" to android.os.Process.myPid()
                    ))
                } else {
                    result.notImplemented()
                }
            }
    }
}
