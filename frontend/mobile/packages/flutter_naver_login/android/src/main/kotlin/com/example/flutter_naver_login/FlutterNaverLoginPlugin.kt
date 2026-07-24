package com.example.flutter_naver_login

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * Android에서는 앱의 Naver OAuth bridge를 사용하므로 자동 등록만 허용하는 호환 Plugin이다.
 *
 * iOS 구현과 공용 Dart API를 유지하면서 Android에서 기존 Plugin이 SDK를 중복 초기화하거나
 * OAuth 설정값을 로그에 출력하지 않도록 한다.
 */
class FlutterNaverLoginPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) = Unit

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) = Unit
}
