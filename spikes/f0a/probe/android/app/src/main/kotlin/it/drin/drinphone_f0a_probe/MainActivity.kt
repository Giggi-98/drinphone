package it.drin.drinphone_f0a_probe

// F0-A probe bridge: Platform Channels -> linphone-sdk-android. NOT product code.
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.linphone.core.Account
import org.linphone.core.Core
import org.linphone.core.CoreListenerStub
import org.linphone.core.Factory
import org.linphone.core.GlobalState
import org.linphone.core.RegistrationState
import org.linphone.core.TransportType

class MainActivity : FlutterActivity() {
    private var core: Core? = null
    private var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())

    private val listener = object : CoreListenerStub() {
        override fun onGlobalStateChanged(core: Core, state: GlobalState?, message: String) =
            emit("global state=${state?.toInt()} msg=$message")

        override fun onAccountRegistrationStateChanged(
            core: Core, account: Account, state: RegistrationState?, message: String
        ) = emit("registration state=${state?.toInt()} msg=$message")
    }

    // Block body: Handler.post returns Boolean, the listener overrides return Unit.
    private fun emit(e: String) {
        main.post { sink?.success(e) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        EventChannel(messenger, "drinphone/f0a/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) { sink = events }
                override fun onCancel(args: Any?) { sink = null }
            })
        MethodChannel(messenger, "drinphone/f0a").setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> {
                    val factory = Factory.instance()
                    val c = factory.createCore(null, null, applicationContext)
                    c.addListener(listener)
                    c.start()
                    core = c
                    result.success(c.version)
                }
                "register" -> {
                    val c = core!!
                    val factory = Factory.instance()
                    val domain = call.argument<String>("domain")!!
                    val params = c.createAccountParams()
                    params.identityAddress =
                        factory.createAddress("sip:${call.argument<String>("user")}@$domain")
                    params.serverAddress = factory.createAddress("sip:$domain")!!
                        .apply { transport = TransportType.Tcp }
                    params.isRegisterEnabled = true
                    val account = c.createAccount(params)
                    c.addAccount(account)
                    c.defaultAccount = account
                    result.success(null)
                }
                "destroy" -> {
                    core?.stop()
                    core?.removeListener(listener)
                    core = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
