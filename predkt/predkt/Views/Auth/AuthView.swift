import SwiftUI

struct AuthView: View {
    @StateObject private var viewModel = AuthViewModel()

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.08).ignoresSafeArea()

            VStack(spacing: 24) {
                // Logo
                VStack(spacing: 12) {
                    Text("🎯")
                        .font(.system(size: 48))
                    Text("Predkt")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 40)

                Spacer()

                // Form
                VStack(spacing: 16) {
                    TextField("Email", text: $viewModel.email)
                        .textFieldStyle(PredktTextFieldStyle())
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("Password", text: $viewModel.password)
                        .textFieldStyle(PredktTextFieldStyle())

                    if viewModel.isSignupMode {
                        TextField("Username", text: $viewModel.username)
                            .textFieldStyle(PredktTextFieldStyle())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(viewModel.isSignupMode && error.contains("created") ? .green : .red)
                            .padding(8)
                            .background(Color(red: 0.15, green: 0.15, blue: 0.2))
                            .cornerRadius(6)
                    }

                    Button(action: {
                        Task {
                            if viewModel.isSignupMode {
                                await viewModel.signup()
                            } else {
                                await viewModel.login()
                            }
                        }
                    }) {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text(viewModel.isSignupMode ? "Sign Up" : "Log In")
                                .font(.system(size: 15, weight: .semibold)) // Fixed: replaced 0.600 with .semibold
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(red: 0.42, green: 0.39, blue: 1.0))
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                    .disabled(viewModel.isLoading)

                    Button(action: { viewModel.isSignupMode.toggle() }) {
                        Text(viewModel.isSignupMode ? "Already have an account? Log in" : "Don't have an account? Sign up")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(red: 0.55, green: 0.52, blue: 1.0))
                    }
                }
                .padding(20)
                .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                .cornerRadius(12)

                Spacer()
            }
            .padding(16)
        }
    }
}

// Fixed: Updated the configuration signature to support modern SwiftUI
struct PredktTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .background(Color(red: 0.1, green: 0.1, blue: 0.12))
            .cornerRadius(8)
            .foregroundStyle(.white)
    }
}

#Preview {
    AuthView()
}
