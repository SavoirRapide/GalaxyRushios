import UIKit
import WebKit
import Capacitor

class AppViewController: CAPBridgeViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            print("⚠️ AppDelegate introuvable")
            return
        }

        // Cherche la WebView dans la hiérarchie
        if let webView = findWebView(in: self.view) {
            appDelegate.injectBridge(webView: webView)
            print("🚀 AppViewController: Bridge injecté via viewDidAppear")
        } else {
            print("⚠️ WebView introuvable dans la hiérarchie")
        }
    }

    private func findWebView(in view: UIView) -> WKWebView? {
        if let wv = view as? WKWebView { return wv }
        for sub in view.subviews {
            if let found = findWebView(in: sub) { return found }
        }
        return nil
    }
}
