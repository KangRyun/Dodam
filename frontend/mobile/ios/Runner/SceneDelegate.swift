import Flutter
import NidThirdPartyLogin
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    let unhandledContexts = Set(
      URLContexts.filter { !NidOAuth.shared.handleURL($0.url) }
    )
    if !unhandledContexts.isEmpty {
      super.scene(scene, openURLContexts: unhandledContexts)
    }
  }
}
