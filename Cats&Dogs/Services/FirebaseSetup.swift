import FirebaseCore
import FirebaseCrashlytics
import Foundation

/// Firebase is optional, like on Android: without `GoogleService-Info.plist` in the app bundle it
/// stays unconfigured and analytics, crash reports and Remote Config fall back to doing nothing / local defaults.
@MainActor
enum FirebaseSetup {
    static var isConfigured: Bool { FirebaseApp.app() != nil }

    static func configureIfAvailable() {
        // `FirebaseApp.configure()` crashes without the plist, so check for it first.
        guard !isConfigured,
              Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil,
              // Unit tests run inside the app; keep their events out of the real project.
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        else { return }
        FirebaseApp.configure()
        // Crash reports from release builds only, as on Android: a debug build's crashes are seen in
        // Xcode, and its dSYM isn't uploaded. Set every launch, as the SDK keeps the last value.
        #if DEBUG
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
        #else
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        #endif
    }
}
