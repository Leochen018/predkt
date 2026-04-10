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

    private let supabaseManager = SupabaseManager.shared

    var isUserVerified: Bool {
        return supabaseManager.user?.confirmedAt != nil
    }

    // --- SIGNUP FLOW ---
    
    func signup() async {
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
        // UPDATED: Relaxed validation to support your 8-character alphanumeric code
        let trimmedCode = otpCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            errorMessage = "Please enter the verification code."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // Pass the trimmed code to the manager
            try await supabaseManager.verifyCode(email: email, code: trimmedCode)
            
            // On success, reset UI state
            self.showingOTPInput = false
            self.isSignupMode = false
            self.errorMessage = nil
            
            // Clear credentials after successful entry
            self.otpCode = ""
            
        } catch {
            // Friendly error for incorrect codes
            errorMessage = "Invalid or expired code. Please try again."
            print("DEBUG: OTP Error: \(error)")
        }

        isLoading = false
    }

    // --- LOGIN & LOGOUT ---

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

    func logout() async {
        isLoading = true
        do {
            try await supabaseManager.logout()
            // Reset all fields on logout
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
