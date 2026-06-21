import Foundation
import Supabase

let supabase: SupabaseClient = {
    let urlString = Bundle.main.infoDictionary?["SupabaseURL"] as? String ?? ""
    let anonKey  = Bundle.main.infoDictionary?["SupabaseAnonKey"] as? String ?? ""
    guard let url = URL(string: urlString), !anonKey.isEmpty else {
        fatalError("Supabase URL or anon key missing from Info.plist / Secrets.xcconfig")
    }
    return SupabaseClient(
        supabaseURL: url,
        supabaseKey: anonKey,
        options: .init(auth: .init(emitLocalSessionAsInitialSession: true))
    )
}()
