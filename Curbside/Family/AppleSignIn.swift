import AuthenticationServices
import CryptoKit
import SwiftUI

/// Sign in with Apple button that produces an `AppleCredential` with a fresh nonce.
struct AppleSignInButton: View {
    var label: SignInWithAppleButton.Label = .signIn
    var onCredential: (AppleCredential) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var nonce = ""

    var body: some View {
        SignInWithAppleButton(label) { request in
            nonce = Self.randomNonce()
            request.requestedScopes = [.fullName]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            guard case .success(let auth) = result,
                  let apple = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = apple.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else { return }
            onCredential(AppleCredential(
                idToken: token,
                rawNonce: nonce,
                authorizationCode: apple.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
                fullName: apple.fullName
            ))
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 50)
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
