import CurbsideCore
import SwiftUI

struct FamilySettingsView: View {
    @Environment(FamilyStore.self) private var store
    @State private var showConsent = false
    @State private var confirmStop = false
    @State private var confirmLeave = false
    @State private var confirmDelete = false
    @State private var memberToRemove: MemberRecord?

    var body: some View {
        let me = store.me
        Form {
            Section {
                Toggle("Share my driving", isOn: Binding(
                    get: { me?.sharing ?? false },
                    set: { on in
                        if on { showConsent = true } else { confirmStop = true }
                    }
                ))
                .disabled(store.isWorking)
                if let role = store.myRole {
                    NavigationLink("What I share") { ConsentView(role: role, mode: .info) }
                }
            } footer: {
                Text(me?.sharing == true
                     ? "Turning this off hides your score from the leaderboard and deletes the drives you've shared."
                     : "Your family can't see your score or drives.")
            }

            if store.isParent {
                Section("Members") {
                    ForEach(store.members.filter { $0.id != me?.id }) { member in
                        HStack {
                            Avatar(name: member.displayName, tier: member.standing?.tier, size: 30)
                            Text(member.displayName)
                            Spacer()
                            Text(member.role.displayName).foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) { memberToRemove = member }
                        }
                    }
                }
            }

            Section {
                Button("Leave \(store.family?.name ?? "family")", role: .destructive) { confirmLeave = true }
            } footer: {
                Text("Deletes everything you've shared with this family. Your own drives stay on your phone.")
            }

            Section {
                Button(store.isDemo ? "Exit demo" : "Sign out") { store.signOut() }
                if !store.isDemo {
                    Button("Delete account", role: .destructive) { confirmDelete = true }
                }
            } footer: {
                if !store.isDemo {
                    Text("Deleting your account removes your profile and everything you've shared. Drives on this phone stay unless you delete them in History.")
                }
            }
        }
        .glassList()
        .navigationTitle("Family settings")
        .sheet(isPresented: $showConsent) {
            if let role = store.myRole {
                NavigationStack { ConsentView(role: role, mode: .review) }
            }
        }
        .confirmationDialog("Stop sharing?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop sharing and delete shared drives", role: .destructive) {
                Task { await store.setSharing(false) }
            }
        } message: {
            Text("Your family will see \"Not sharing\". Your drives stay on your phone.")
        }
        .confirmationDialog("Leave the family?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave and delete what I shared", role: .destructive) {
                Task { await store.leaveFamily() }
            }
        }
        .confirmationDialog(
            "Remove \(memberToRemove?.displayName ?? "")?",
            isPresented: Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }),
            titleVisibility: .visible,
            presenting: memberToRemove
        ) { member in
            Button("Remove and delete their shared drives", role: .destructive) {
                Task { await store.remove(member) }
            }
        }
        .sheet(isPresented: $confirmDelete) { DeleteAccountSheet() }
    }
}

/// Apple requires a fresh sign-in to revoke the account's Apple token when deleting.
private struct DeleteAccountSheet: View {
    @Environment(FamilyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .font(.system(size: 52))
                    .foregroundStyle(DS.Palette.coral)
                Text("Delete your Curbside account?").font(.title3.weight(.bold))
                Text("This removes your profile, takes you out of your family, and deletes everything you've shared. It can't be undone.\n\nConfirm with Apple to continue.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                AppleSignInButton(label: .continue) { credential in
                    Task {
                        await store.deleteAccount(confirmingWith: credential)
                        dismiss()
                    }
                }
                .disabled(store.isWorking)
                if store.isWorking { ProgressView() }
                Spacer()
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
