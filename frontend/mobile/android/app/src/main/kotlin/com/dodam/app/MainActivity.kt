package com.dodam.app

import android.content.pm.PackageManager
import com.navercorp.nid.NidOAuth
import com.navercorp.nid.core.data.datastore.NidOAuthInitializingCallback
import com.navercorp.nid.oauth.util.NidOAuthCallback
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter 화면과 Android Naver Login SDK 사이의 OAuth 호출을 연결한다.
 *
 * flutter_naver_login의 Android 구현 대신 앱이 사용하는 SDK 버전에 맞춘 최소 계약만 노출하며,
 * OAuth 설정값이나 발급된 Token은 로그에 기록하지 않는다.
 */
class MainActivity : FlutterFragmentActivity() {
    private companion object {
        const val CHANNEL_NAME = "com.dodam.app/naver_oauth"
        const val CLIENT_ID_KEY = "com.dodam.naver.clientId"
        const val CLIENT_SECRET_KEY = "com.dodam.naver.clientSecret"
        const val CLIENT_NAME_KEY = "com.dodam.naver.clientName"
    }

    private var channel: MethodChannel? = null
    private var pendingLoginResult: MethodChannel.Result? = null
    private var isNaverSdkReady = false
    private var naverInitializationFailed = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "login" -> loginWithNaver(result)
                "logout" -> logoutFromNaver(result)
                else -> result.notImplemented()
            }
        }
        initializeNaverSdk()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        NidOAuth.oauthLoginCallback = null
        completeLoginError("NAVER_LOGIN_INTERRUPTED", "Naver login was interrupted.")
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun initializeNaverSdk() {
        val metadata =
            packageManager.getApplicationInfo(
                packageName,
                PackageManager.GET_META_DATA,
            ).metaData
        val clientId = metadata.getString(CLIENT_ID_KEY).orEmpty()
        val clientSecret = metadata.getString(CLIENT_SECRET_KEY).orEmpty()
        val clientName = metadata.getString(CLIENT_NAME_KEY).orEmpty()
        require(clientId.isNotBlank() && clientSecret.isNotBlank() && clientName.isNotBlank()) {
            "Naver OAuth configuration is missing"
        }
        NidOAuth.setLogEnabled(false)
        NidOAuth.initialize(
            applicationContext,
            clientId,
            clientSecret,
            clientName,
            object : NidOAuthInitializingCallback {
                override fun onSuccess() {
                    isNaverSdkReady = true
                    pendingLoginResult?.let { requestNaverLogin() }
                }

                override fun onFailure(e: Exception) {
                    runOnUiThread {
                        naverInitializationFailed = true
                        completeLoginError(
                            "NAVER_CONFIGURATION_INVALID",
                            "Naver OAuth initialization failed.",
                        )
                    }
                }
            },
        )
    }

    private fun loginWithNaver(result: MethodChannel.Result) {
        if (pendingLoginResult != null) {
            result.error("NAVER_LOGIN_IN_PROGRESS", "Naver login is already in progress.", null)
            return
        }
        pendingLoginResult = result
        when {
            isNaverSdkReady -> requestNaverLogin()
            naverInitializationFailed ->
                completeLoginError(
                    "NAVER_CONFIGURATION_INVALID",
                    "Naver OAuth initialization failed.",
                )
        }
    }

    private fun requestNaverLogin() {
        if (pendingLoginResult == null) return
        NidOAuth.requestLogin(
            context = this,
            callback =
                object : NidOAuthCallback {
                    override fun onSuccess() {
                        val accessToken = NidOAuth.getAccessToken()
                        if (accessToken.isNullOrBlank()) {
                            completeLoginError(
                                "NAVER_TOKEN_MISSING",
                                "Naver did not issue an access token.",
                            )
                            return
                        }
                        pendingLoginResult?.success(accessToken)
                        pendingLoginResult = null
                    }

                    override fun onFailure(errorCode: String, errorDesc: String) {
                        val code =
                            if (errorCode.contains("cancel", ignoreCase = true)) {
                                "NAVER_LOGIN_CANCELLED"
                            } else {
                                "NAVER_LOGIN_FAILED"
                            }
                        completeLoginError(code, "Naver login was not completed.")
                    }
                },
        )
    }

    private fun logoutFromNaver(result: MethodChannel.Result) {
        NidOAuth.disconnect(
            object : NidOAuthCallback {
                override fun onSuccess() {
                    result.success(null)
                }

                override fun onFailure(errorCode: String, errorDesc: String) {
                    result.error("NAVER_LOGOUT_FAILED", "Naver logout was not completed.", null)
                }
            },
        )
    }

    private fun completeLoginError(code: String, message: String) {
        pendingLoginResult?.error(code, message, null)
        pendingLoginResult = null
    }
}
