import SwiftUI

private enum SignupRole: String, CaseIterable, Identifiable {
    case athlete = "Athlete"
    case volunteer = "Volunteer"
    case headCoach = "Head Coach (approval required)"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .athlete: "figure.run"
        case .volunteer: "heart.fill"
        case .headCoach: "person.badge.key.fill"
        }
    }

    var memberRole: MemberRole {
        switch self {
        case .athlete: .athlete
        case .volunteer, .headCoach: .volunteer
        }
    }
}

struct SignInView: View {
    enum Mode { case signIn, signUp, verify, resetRequest, resetConfirm }

    @EnvironmentObject private var authentication: Authentication
    @EnvironmentObject private var model: AppModel
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var newPassword = ""
    @State private var verificationCode = ""
    @State private var selectedRole: SignupRole = .athlete
    @State private var name = ""
    @State private var age = ""
    @State private var phone = ""
    @State private var organization = ""
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
                            ForEach(SignupRole.allCases) { role in
                                Label(role.rawValue, systemImage: role.icon).tag(role)
                            }
                        }
                        .pickerStyle(.navigationLink)
                        if selectedRole == .headCoach {
                            Text("Head Coach controls are enabled only after a current Head Coach approves the account.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section("Your profile") {
                        TextField("Full name", text: $name)
                            .textContentType(.name)
                        TextField("Phone number", text: $phone)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                        TextField("Age", text: $age)
                            .keyboardType(.numberPad)
                        if selectedRole == .volunteer || selectedRole == .headCoach {
                            TextField("Company or school (optional)", text: $organization)
                        }
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
        case .signUp: "Send verification code"
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
        case .signUp: "Choose your role and enter your phone number once. There is no second sign-in."
        case .verify: "Enter the verification code sent to \(email)."
        case .resetRequest: "We’ll email a code to reset your password."
        case .resetConfirm: "Enter the reset code sent to \(email)."
        }
    }

    private var canContinue: Bool {
        switch mode {
        case .verify: !verificationCode.isEmpty
        case .resetConfirm: !verificationCode.isEmpty && newPassword.count >= 8
        case .signIn: email.contains("@") && password.count >= 8
        case .signUp:
            email.contains("@") && password.count >= 8 &&
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            Int(age.trimmingCharacters(in: .whitespacesAndNewlines)) != nil &&
            phone.filter(\.isNumber).count >= 7
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
                    try await authentication.signIn(email: email, password: password)
                    guard let years = Int(age.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
                    let profile = Authentication.OnboardingProfile(
                        role: selectedRole.memberRole,
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        age: years,
                        phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
                        organization: organization.trimmingCharacters(in: .whitespacesAndNewlines),
                        requestedHeadCoach: selectedRole == .headCoach
                    )
                    authentication.saveOnboardingProfile(profile, for: email)
                    model.completeSignup(
                        role: profile.role,
                        name: profile.name,
                        age: profile.age,
                        contact: profile.phone,
                        organization: profile.organization,
                        sports: []
                    )
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
