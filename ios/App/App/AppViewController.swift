import UIKit
import Capacitor

class AppViewController: CAPBridgeViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
              let webView = self.webView else {
            print("⚠️ Impossible d'injecter le bridge")
            return
        }

        appDelegate.injectBridge(webView: webView)
        print("🚀 AppViewController: Bridge injecté via viewDidLoad")
    }
}
