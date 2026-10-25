import SwiftUI
import SwiftData
import GoogleSignIn
import FirebaseCore

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // FirebaseApp.configure() crashes without GoogleService-Info.plist, so skip it when the file is absent
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
        return true
    }
}

@main
struct DailyJollyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container = AppModelContainer.make()
    @State private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if settings.isAppUnlocked {
                    MainView()
                } else {
                    AppLockView()
                }
            }
            .preferredColorScheme(settings.theme.colorScheme)
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
        .modelContainer(container)
    }
}
