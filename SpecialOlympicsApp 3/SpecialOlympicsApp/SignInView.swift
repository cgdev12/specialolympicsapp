import SwiftUI

struct SignInView: View {
    enum Mode { case signIn, signUp, verify }

    @EnvironmentObject private var authentication: Authentication
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var verificationCode = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(mode == .signIn ? "Welcome back" : mode == .signUp ? "Create your account" : "Check your email")
                        .font(.title2.bold())
                    Text(mode == .verify ? "Enter the verification code sent to \(email)." : "Sign in to 212so to continue.")
                        .foregroundStyle(.secondary)
                }
                if mode != .verify {
                    Section {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $password)
                            .textContentType(mode == .signIn ? .password : .newPassword)
                    }
                } else {
                    Section {
                        TextField("Verification code", text: $verificationCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                    }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
                Section {
                    Button(mainButtonTitle, action: performMainAction)
                        .disabled(authentication.isWorking || !canContinue)
                    if mode == .signIn {
                        Button("Create an account") { mode = .signUp; errorMessage = nil }
                    } else {
                        Button("Back to sign in") { mode = .signIn; errorMessage = nil }
                    }
                }
            }
            .navigationTitle("212so")
            .overlay { if authentication.isWorking { ProgressView() } }
        }
    }

    private var mainButtonTitle: String {
        switch mode { case .signIn: "Sign in"; case .signUp: "Send verification code"; case .verify: "Verify account" }
    }

    private var canContinue: Bool {
        switch mode {
        case .verify: !verificationCode.isEmpty
        case .signIn, .signUp: email.contains("@") && password.count >= 8
        }
    }

    private func performMainAction() {
        Task {
            do {
                errorMessage = nil
                switch mode {
                case .signIn: try await authentication.signIn(email: email, password: password)
                case .signUp:
                    try await authentication.startSignUp(email: email, password: password)
                    mode = .verify
                case .verify:
                    try await authentication.verifySignUp(email: email, code: verificationCode)
                    try await authentication.signIn(email: email, password: password)
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
