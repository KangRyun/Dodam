import Flutter
import GoogleSignIn
import KakaoSDKAuth
import NidThirdPartyLogin
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    let unhandledContexts = Set(
      URLContexts.filter { context in
        let url = context.url

        if NidOAuth.shared.handleURL(url) {
          return false
        }

        if AuthApi.isKakaoTalkLoginUrl(url) {
          _ = AuthController.handleOpenUrl(url: url)
          return false
        }

        if GIDSignIn.sharedInstance.handle(url) {
          return false
        }

        return true
      }
    )

    if !unhandledContexts.isEmpty {
      super.scene(scene, openURLContexts: unhandledContexts)
    }
  }
}
