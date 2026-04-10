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

                // Form Container
                VStack(spacing: 16) {
                    if viewModel.showingOTPInput {
                        // --- OTP VERIFICATION UI ---
                        VStack(spacing: 12) {
                            Text("Verify your Email")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                            
                            Text("Enter the code sent to\n\(viewModel.email)")
                                .font(.system(size: 13))
                                .foregroundStyle(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.bottom, 8)

                            // UPDATED: Changed keyboard and capitalization for 8-char alphanumeric
                            TextField("Enter Code", text: $viewModel.otpCode)
                                .textFieldStyle(PredktTextFieldStyle())
                                .keyboardType(.default)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .textContentType(.oneTimeCode)
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .multilineTextAlignment(.center)
                        }
                        
                        Button(action: {
                            Task { await viewModel.verifyOTP() }
                        }) {
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Verify & Sign In")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(red: 0.42, green: 0.39, blue: 1.0))
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                        
                        Button(action: { viewModel.showingOTPInput = false }) {
                            Text("Back to Sign Up")
                                .font(.system(size: 13))
                                .foregroundStyle(.gray)
                        }

                    } else {
                        // --- REGULAR LOGIN / SIGNUP UI ---
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
                                    .font(.system(size: 15, weight: .semibold))
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
                    
                    // Error Message Display
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
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
    // Add this at the very end of AuthView.swift
    struct PredktTextFieldStyle: TextFieldStyle {
        func _body(configuration: TextField<Self._Label>) -> some View {
            configuration
                .padding(12)
                .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                .cornerRadius(8)
                .foregroundStyle(.white)
                .tint(Color(red: 0.42, green: 0.39, blue: 1.0)) // Purple cursor
        }
    }
}
