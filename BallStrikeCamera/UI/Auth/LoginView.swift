import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: AuthSessionStore
    @StateObject private var vm = AuthViewModel()
    @State private var showCreate = false

    var body: some View {
        ZStack {
            TrueCarryBackground()
                .ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 72)
                    logoSection
                    Spacer(minLength: 52)
                    formCard
                    Spacer(minLength: 20)
                    createAccountButton
                    Spacer(minLength: 16)
                    guestButton
                    Spacer(minLength: 48)
                }
                .padding(.horizontal, TCTheme.hPad)
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateAccountView()
                .environmentObject(session)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Logo

    private var logoSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(TCTheme.panelRaised)
                    .frame(width: 88, height: 88)
                Circle()
                    .strokeBorder(TCTheme.goldGradient, lineWidth: 2)
                    .frame(width: 88, height: 88)
                Image(systemName: "figure.golf")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundColor(TCTheme.gold)
            }

            Text("TRUE CARRY")
                .font(.system(size: 30, weight: .black))
                .tracking(3)
                .foregroundColor(TCTheme.textPrimary)

            Text("Golf launch monitor · Performance tracking")
                .font(.system(size: 13))
                .foregroundColor(TCTheme.textMuted)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Form

    private var formCard: some View {
        VStack(spacing: 16) {
            Text("Sign In")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            TCAuthTextField(placeholder: "Email", text: $vm.email, icon: "envelope")
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .textInputAutocapitalization(.never)

            TCAuthTextField(placeholder: "Password", text: $vm.password, icon: "lock", isSecure: true)

            if let err = vm.errorMessage {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundColor(TCTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            TCPrimaryGoldButton(
                title: vm.isLoading ? "Signing in…" : "Sign In",
                icon: "arrow.right.circle.fill"
            ) {
                Task { await vm.signIn(store: session) }
            }
            .disabled(vm.isLoading)
            .opacity(vm.isLoading ? 0.6 : 1)
        }
        .tcCard()
    }

    // MARK: Create / Guest

    private var createAccountButton: some View {
        Button { showCreate = true } label: {
            HStack(spacing: 6) {
                Text("Don't have an account?")
                    .foregroundColor(TCTheme.textMuted)
                Text("Create one")
                    .foregroundColor(TCTheme.gold)
                    .fontWeight(.semibold)
            }
            .font(.system(size: 14))
        }
        .buttonStyle(.plain)
    }

    private var guestButton: some View {
        Button {
            Task { await vm.continueAsGuest(store: session) }
        } label: {
            Text("Continue as Guest")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(TCTheme.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(TCTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(TCTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Create Account View

struct CreateAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: AuthSessionStore
    @StateObject private var vm = AuthViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                TrueCarryBackground()
                    .ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        Text("Create Account")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(TCTheme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(spacing: 14) {
                            TCAuthTextField(placeholder: "Full Name", text: $vm.name, icon: "person")
                            TCAuthTextField(placeholder: "Email", text: $vm.email, icon: "envelope")
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .textInputAutocapitalization(.never)
                            TCAuthTextField(placeholder: "Password (6+ chars)", text: $vm.password, icon: "lock", isSecure: true)
                        }

                        if let err = vm.errorMessage {
                            Text(err)
                                .font(.system(size: 13))
                                .foregroundColor(TCTheme.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        TCPrimaryGoldButton(
                            title: vm.isLoading ? "Creating…" : "Create Account",
                            icon: "person.badge.plus"
                        ) {
                            Task { await vm.createAccount(store: session) }
                        }
                        .disabled(vm.isLoading)
                        .opacity(vm.isLoading ? 0.6 : 1)

                        Text("Your data is stored locally on this device. No account info is sent to a server.")
                            .font(.system(size: 11))
                            .foregroundColor(TCTheme.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 12)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(TCTheme.textMuted)
                }
            }
            .onChange(of: session.isLoggedIn) { loggedIn in
                if loggedIn { dismiss() }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Reusable auth text field (TCTheme)

struct TCAuthTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String = ""
    var isSecure: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(TCTheme.textMuted)
                    .frame(width: 20)
            }
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(.system(size: 15))
            .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(TCTheme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(TCTheme.border, lineWidth: 1)
        )
    }
}
