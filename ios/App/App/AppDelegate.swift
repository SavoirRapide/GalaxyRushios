import UIKit
import WebKit
import Capacitor
import AVFoundation
import Appodeal

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    private let appodealAppKey = "23c5dc7ba8ef7a9104b712ffec317572d15682dee76aa870"
    private var appodealInitialized = false
    private var appodealStarted = false
    private var rewardEarned = false
    private weak var activeWebView: WKWebView?
    private var bridgeInjected = false

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }

        // Polling pour trouver la WebView
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.findAndInjectBridge()
        }

        return true
    }

    // ══════════════════════════════════════════════
    // MARK: - Appodeal Init (dans applicationDidBecomeActive)
    // ══════════════════════════════════════════════

    func applicationDidBecomeActive(_ application: UIApplication) {
        if !appodealStarted {
            appodealStarted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.doAppodealInit()
            }
        }
    }

    private func doAppodealInit() {
        if appodealInitialized { return }
        print("🔴 AVANT Appodeal.initialize()")
        Appodeal.setLogLevel(.verbose)
        Appodeal.setInitializationDelegate(self)
        Appodeal.initialize(
            withApiKey: appodealAppKey,
            types: [.interstitial, .rewardedVideo]
        )
        print("🔴 APRÈS Appodeal.initialize()")
    }

    // ══════════════════════════════════════════════
    // MARK: - Trouver la WebView et injecter le bridge
    // ══════════════════════════════════════════════

    private func findAndInjectBridge() {
        if bridgeInjected { return }

        guard let rootVC = window?.rootViewController else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.findAndInjectBridge()
            }
            return
        }

        if let webView = findWebView(in: rootVC.view) {
            injectBridge(webView: webView)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.findAndInjectBridge()
            }
        }
    }

    private func findWebView(in view: UIView) -> WKWebView? {
        if let wv = view as? WKWebView { return wv }
        for sub in view.subviews {
            if let found = findWebView(in: sub) { return found }
        }
        return nil
    }

    // ══════════════════════════════════════════════
    // MARK: - Bridge injection
    // ══════════════════════════════════════════════

    func injectBridge(webView: WKWebView) {
        if bridgeInjected { return }
        bridgeInjected = true
        self.activeWebView = webView

        let bridgeScript = """
        window.AppodealBridge = {
            initAds: function() {
                window.webkit.messageHandlers.appodealBridge.postMessage({ action: "initAds" });
            },
            showInterstitial: function() {
                window.webkit.messageHandlers.appodealBridge.postMessage({ action: "showInterstitial" });
            },
            showRewarded: function() {
                window.webkit.messageHandlers.appodealBridge.postMessage({ action: "showRewarded" });
            },
            isLoaded: function(type) {
                return true;
            }
        };
        console.log("🍎 AppodealBridge iOS injecté !");
        """

        let userScript = WKUserScript(
            source: bridgeScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        webView.configuration.userContentController.addUserScript(userScript)

        webView.configuration.userContentController.add(
            AppodealMessageHandler(delegate: self),
            name: "appodealBridge"
        )

        // Injecter aussi maintenant si la page est déjà chargée
        webView.evaluateJavaScript(bridgeScript) { _, error in
            if let error = error {
                print("⚠️ Injection directe erreur: \(error)")
            } else {
                print("✅ Bridge injecté directement dans la page courante")
            }
        }

        // Si Appodeal est déjà init, notifier le JS maintenant
        if appodealInitialized {
            notifyJS(event: "onAdsInitialized", data: "true")
        }

        print("🚀 AppodealBridge iOS configuré.")
    }

    // ══════════════════════════════════════════════
    // MARK: - Appodeal Init (appelé par JS — fallback)
    // ══════════════════════════════════════════════

    func initAppodeal() {
        if appodealInitialized {
            notifyJS(event: "onAdsInitialized", data: "true")
            return
        }
        doAppodealInit()
    }

    // ══════════════════════════════════════════════
    // MARK: - Show Ads
    // ══════════════════════════════════════════════

    func showInterstitial() {
        guard let rootVC = window?.rootViewController else { return }
        if Appodeal.isReadyForShow(with: .interstitial) {
            Appodeal.showAd(.interstitial, rootViewController: rootVC)
        } else {
            print("⚠️ Appodeal: Interstitiel pas chargé.")
        }
    }

    func showRewarded() {
        guard let rootVC = window?.rootViewController else { return }
        rewardEarned = false
        if Appodeal.isReadyForShow(with: .rewardedVideo) {
            Appodeal.showAd(.rewardedVideo, rootViewController: rootVC)
        } else {
            print("⚠️ Appodeal: Rewarded pas chargée.")
            notifyJS(event: "onRewardedFailed", data: "not_loaded")
        }
    }

    // ══════════════════════════════════════════════
    // MARK: - JS Communication
    // ══════════════════════════════════════════════

    func notifyJS(event: String, data: String) {
        guard let wv = activeWebView else { return }
        let js = "window.dispatchEvent(new CustomEvent('\(event)', {detail:'\(data)'}));"
        DispatchQueue.main.async {
            wv.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // ══════════════════════════════════════════════
    // MARK: - Lifecycle
    // ══════════════════════════════════════════════

    func applicationWillResignActive(_ application: UIApplication) {}
    func applicationDidEnterBackground(_ application: UIApplication) {}
    func applicationWillEnterForeground(_ application: UIApplication) {}
    func applicationWillTerminate(_ application: UIApplication) {}

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }
}

// ══════════════════════════════════════════════
// MARK: - WKScriptMessageHandler
// ══════════════════════════════════════════════

class AppodealMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: AppDelegate?

    init(delegate: AppDelegate) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "initAds":
            delegate?.initAppodeal()
        case "showInterstitial":
            delegate?.showInterstitial()
        case "showRewarded":
            delegate?.showRewarded()
        default:
            print("⚠️ AppodealBridge: action inconnue '\(action)'")
        }
    }
}

// ══════════════════════════════════════════════
// MARK: - Appodeal Initialization Delegate
// ══════════════════════════════════════════════

extension AppDelegate: AppodealInitializationDelegate {
    func appodealSDKDidInitialize() {
        print("✅ Appodeal initialisé (iOS) !")
        appodealInitialized = true
        Appodeal.setInterstitialDelegate(self)
        Appodeal.setRewardedVideoDelegate(self)
        notifyJS(event: "onAdsInitialized", data: "true")
    }
}

// ══════════════════════════════════════════════
// MARK: - Interstitial Delegate
// ══════════════════════════════════════════════

extension AppDelegate: AppodealInterstitialDelegate {
    func interstitialDidLoadAdIsPrecache(_ precache: Bool) {}
    func interstitialDidFailToLoadAd() {}
    func interstitialWillPresent() {}
    func interstitialDidFailToPresent() {}
    func interstitialDidClick() {}
    func interstitialDidExpired() {}
    func interstitialDidDismiss() {
        notifyJS(event: "onInterstitialClosed", data: "true")
    }
}

// ══════════════════════════════════════════════
// MARK: - Rewarded Video Delegate
// ══════════════════════════════════════════════

extension AppDelegate: AppodealRewardedVideoDelegate {
    func rewardedVideoDidLoadAdIsPrecache(_ precache: Bool) {}
    func rewardedVideoDidFailToLoadAd() {}
    func rewardedVideoDidPresent() {}
    func rewardedVideoDidClick() {}
    func rewardedVideoDidExpired() {}

    func rewardedVideoDidFailToPresentWithError(_ error: Error) {
        notifyJS(event: "onRewardedFailed", data: "show_failed")
    }

    func rewardedVideoDidFinish(_ rewardAmount: Float, name rewardName: String?) {
        rewardEarned = true
    }

    func rewardedVideoWillDismissAndWasFullyWatched(_ wasFullyWatched: Bool) {
        if rewardEarned || wasFullyWatched {
            notifyJS(event: "onRewardEarned", data: "true")
        } else {
            notifyJS(event: "onRewardedFailed", data: "not_finished")
        }
        rewardEarned = false
        notifyJS(event: "onAdClosed", data: "true")
    }
}
