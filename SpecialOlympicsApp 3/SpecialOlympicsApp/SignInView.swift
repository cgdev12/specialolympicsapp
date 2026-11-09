import SwiftUI

struct SignInView: View {
    enum Mode { case signIn, signUp, verify, resetRequest, resetConfirm }

    @EnvironmentObject private var authentication: Authentication
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var newPassword = ""
    @State private var verificationCode = ""
    @State private var selectedRole: MemberRole = .athlete
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(title)
                        .font(.title2.bold())
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                if mode == .signIn || mode == .signUp || mode == .resetRequest {
                    Section {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                        if mode != .resetRequest {
                            SecureField("Password", text: $password)
                            .textContentType(mode == .signIn ? .password : .newPassword)
                        }
                    }
                }
                if mode == .signUp {
                    Section("How will you use 212so?") {
                        Picker("Role", selection: $selectedRole) {
                            ForEach(MemberRole.allCases.filter { $0 != .admin }) { role in
                                Label(role.rawValue, systemImage: role.icon).tag(role)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }
                if mode == .verify || mode == .resetConfirm {
                    Section {
                        TextField("Verification code", text: $verificationCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        if mode == .resetConfirm {
                            SecureField("New password", text: $newPassword)
                                .textContentType(.newPassword)
                        }
                    }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
                Section {
                    Button(mainButtonTitle, action: performMainAction)
                        .disabled(authentication.isWorking || !canContinue)
                    if mode == .signIn {
                        Button("Create an account") { mode = .signUp; errorMessage = nil }
                        Button("Forgot password?") { mode = .resetRequest; errorMessage = nil }
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
        switch mode {
        case .signIn: "Sign in"
        case .signUp: "Create account"
        case .verify: "Verify account"
        case .resetRequest: "Send reset code"
        case .resetConfirm: "Reset password"
        }
    }

    private var title: String {
        switch mode {
        case .signIn: "Welcome back"
        case .signUp: "Create your account"
        case .verify: "Check your email"
        case .resetRequest: "Reset your password"
        case .resetConfirm: "Choose a new password"
        }
    }

    private var subtitle: String {
        switch mode {
        case .signIn: "Sign in to 212so to continue."
        case .signUp: "Choose your role now, then finish your profile in onboarding."
        case .verify: "Enter the verification code sent to \(email)."
        case .resetRequest: "We’ll email a code to reset your password."
        case .resetConfirm: "Enter the reset code sent to \(email)."
        }
    }

    private var canContinue: Bool {
        switch mode {
        case .verify: !verificationCode.isEmpty
        case .resetConfirm: !verificationCode.isEmpty && newPassword.count >= 8
        case .signIn, .signUp: email.contains("@") && password.count >= 8
        case .resetRequest: email.contains("@")
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
                    authentication.saveOnboardingRole(selectedRole, for: email)
                    try await authentication.signIn(email: email, password: password)
                case .resetRequest:
                    try await authentication.requestPasswordReset(email: email)
                    verificationCode = ""
                    newPassword = ""
                    mode = .resetConfirm
                case .resetConfirm:
                    try await authentication.confirmPasswordReset(email: email, code: verificationCode, newPassword: newPassword)
                    password = newPassword
                    mode = .signIn
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
