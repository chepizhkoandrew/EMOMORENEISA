import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct EMOMORENEISAApp: App {
    @State private var authState = AuthState.shared

    init() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: "353195660969-ff6luandfvauj7odempe0k2imsnh98k5.apps.googleusercontent.com"
        )
    }

    private static let modelContainer: ModelContainer = {
        let schema = Schema([
            LocalStudentProfile.self,
            LocalChatSession.self,
            LocalChatMessage.self,
            ParrotPhrase.self,
            MemoryCard.self,
            StreetAnnotation.self,
            VerbAttempt.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(authState)
                .modelContainer(Self.modelContainer)
                .task { await authState.restoreSession() }
        }
    }
}
