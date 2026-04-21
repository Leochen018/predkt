import Foundation
import Combine
import Supabase

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var username = ""
    @Published var otpCode = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isSignupMode = false
    @Published var showingOTPInput = false

    // Step 2 — offline banner state (read by your views to show a banner)
    @Published var isOffline = false

    private let supabaseManager = SupabaseManager.shared
    private let network = NetworkMonitor.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Step 2 — watch network state so views can show an offline banner
        network.$isConnected
            .receive(on: RunLoop.main)
            .sink { [weak self] connected in
                self?.isOffline = !connected
            }
            .store(in: &cancellables)
    }

    // --- SIGNUP FLOW ---

    func signup() async {
        // Step 3 — offline guard: tell user immediately instead of waiting for a timeout
        guard network.isConnected else {
            errorMessage = "No connection — can't sign up right now"
            return
        }

        guard !username.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please choose a username."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            try await supabaseManager.signup(
                email: email,
                password: password,
                username: username
            )

            // Success: Switch to OTP input
            self.showingOTPInput = true
            self.errorMessage = "Code sent! Check your email."

        } catch {
            errorMessage = error.localizedDescription
            print("DEBUG: Signup Error: \(error)")
        }

        isLoading = false
    }

    // --- OTP VERIFICATION FLOW ---

    func verifyOTP() async {
        // Step 3 — offline guard
        guard network.isConnected else {
            errorMessage = "No connection — can't verify right now"
            return
        }

        let trimmedCode = otpCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            errorMessage = "Please enter the verification code."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            try await supabaseManager.verifyCode(email: email, code: trimmedCode)

            // On success, reset UI state
            self.showingOTPInput = false
            self.isSignupMode = false
            self.errorMessage = nil
            self.otpCode = ""

        } catch {
            errorMessage = "Invalid or expired code. Please try again."
            print("DEBUG: OTP Error: \(error)")
        }

        isLoading = false
    }

    // --- LOGIN & LOGOUT ---

    func login() async {
        // Step 3 — offline guard
        guard network.isConnected else {
            errorMessage = "No connection — check your signal and try again"
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            try await supabaseManager.login(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func logout() async {
        // Note: logout intentionally clears all fields — this is correct behaviour.
        // No offline guard here: we clear local state regardless of connection.
        isLoading = true
        do {
            try await supabaseManager.logout()
            email = ""
            password = ""
            username = ""
            otpCode = ""
            errorMessage = nil
            showingOTPInput = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
