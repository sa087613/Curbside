import CurbsideCore
import SwiftUI

/// Family tab: walks through sign-in → name → create/join → consent, then shows the family.
struct FamilyTabView: View {
    @Environment(FamilyStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                switch store.phase {
                case .loading:
                    ProgressView()
                case .signedOut:
                    SignInView()
                case .needsName:
                    NameStepView()
                case .needsFamily:
                    FamilySetupView()
                case .needsConsent:
                    if let role = store.myRole {
                        ConsentView(role: role, mode: .firstTime)
                    } else {
                        ProgressView()
                    }
                case .ready:
                    FamilyHomeView()
                }
            }
            .safeAreaInset(edge: .top) {
                if store.isDemo { DemoBanner() }
            }
        }
    }
}

private struct DemoBanner: View {
    @Environment(FamilyStore.self) private var store

    var body: some View {
        HStack {
            Label("Demo family: made-up members, nothing is uploaded", systemImage: "theatermasks")
                .font(.caption.weight(.semibold))
            Spacer()
            Button("Exit") { store.exitDemo() }
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DS.Palette.accent.opacity(0.25))
    }
}

// MARK: - Sign in

private struct SignInView: View {
    @Environment(FamilyStore.self) private var store
    @State private var showDemoChoice = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "figure.2.and.child.holdinghands")
                    .font(.system(size: 64))
                    .foregroundStyle(DS.Palette.accent)
                    .padding(.top, 32)
                VStack(spacing: 8) {
                    Text("Drive better together").font(.title2.weight(.bold))
                    Text("Create a family, see how everyone's driving, and climb the family leaderboard.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Bullet(symbol: "person.badge.key", text: "Parents invite teens with a code.")
                    Bullet(symbol: "hand.raised", text: "Teens choose what to share, and can stop anytime.")
                    Bullet(symbol: "trophy", text: "Everyone, parents too, on one leaderboard.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if store.isFirebaseAvailable {
                    AppleSignInButton { credential in
                        Task { await store.signIn(with: credential) }
                    }
                    .disabled(store.isWorking)
                    Text("Driving and scores work without an account. You only need one for family features.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Family sign-in isn't set up in this build (GoogleService-Info.plist is missing).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button("Preview with a demo family") { showDemoChoice = true }
                    .confirmationDialog("Preview as…", isPresented: $showDemoChoice) {
                        Button("A parent") { store.startDemo(as: .parent) }
                        Button("A teen") { store.startDemo(as: .teen) }
                    } message: {
                        Text("Made-up family members. Nothing is uploaded.")
                    }
            }
            .padding(24)
        }
        .screenBackground()
        .navigationTitle("Family")
    }
}

private struct Bullet: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(DS.Palette.accent)
                .frame(width: 28)
            Text(text)
        }
    }
}

// MARK: - Name

private struct NameStepView: View {
    @Environment(FamilyStore.self) private var store
    @State private var name = ""

    var body: some View {
        Form {
            Section {
                TextField("First name", text: $name)
                    .textContentType(.givenName)
                    .submitLabel(.continue)
                    .onSubmit(save)
            } header: {
                Text("What should your family call you?")
            } footer: {
                Text("Shown on the family leaderboard.")
            }
            Button("Continue", action: save)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || store.isWorking)
        }
        .glassList()
        .navigationTitle("Welcome")
        .onAppear { if name.isEmpty { name = store.suggestedName } }
    }

    private func save() {
        Task { await store.setName(name) }
    }
}

// MARK: - Create or join

private struct FamilySetupView: View {
    @Environment(FamilyStore.self) private var store
    @State private var familyName = ""
    @State private var code = ""
    @State private var foundInvite: InviteInfo?

    var body: some View {
        Form {
            Section {
                TextField("Family name (e.g. The Rivera family)", text: $familyName)
                Button("Create family") {
                    Task { await store.createFamily(named: familyName) }
                }
                .disabled(store.isWorking)
            } header: {
                Text("I'm a parent")
            } footer: {
                Text("You'll get a code to invite your teens and other parents.")
            }

            Section {
                TextField("ABCD-EFGH", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.title3.monospaced())
                Button("Find family") {
                    Task { foundInvite = await store.lookupInvite(code) }
                }
                .disabled(InviteCode.normalize(code) == nil || store.isWorking)
            } header: {
                Text("I have an invite code")
            } footer: {
                Text("Ask a parent in your family for their 8-character code.")
            }

            Section {
                Button("Sign out", role: .destructive) { store.signOut() }
            }
        }
        .glassList()
        .navigationTitle("Your family")
        .confirmationDialog(
            foundInvite.map { "Join \($0.familyName) as a \($0.role.displayName.lowercased())?" } ?? "",
            isPresented: Binding(get: { foundInvite != nil }, set: { if !$0 { foundInvite = nil } }),
            titleVisibility: .visible,
            presenting: foundInvite
        ) { invite in
            Button("Join") { Task { await store.join(invite) } }
            Button("Cancel", role: .cancel) {}
        } message: { invite in
            Text(invite.role == .teen
                 ? "Next, you'll choose what to share with the parents. Nothing is shared until you agree."
                 : "You'll be able to see drives from teens who choose to share.")
        }
    }
}
