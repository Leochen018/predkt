import Foundation
import Combine

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var username = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isSignupMode = false

    private let supabaseManager = SupabaseManager.shared

    func login() async {
        isLoading = true
        errorMessage = nil

        do {
            try await supabaseManager.login(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func signup() async {
        isLoading = true
        errorMessage = nil

        guard !username.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Username cannot be empty"
            isLoading = false
            return
        }

        do {
            try await supabaseManager.signup(email: email, password: password, username: username)
            errorMessage = "Account created! Check your email to verify."
            // Clear form
            email = ""
            password = ""
            username = ""
            isSignupMode = false
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func logout() async {
        isLoading = true
        do {
            try await supabaseManager.logout()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
