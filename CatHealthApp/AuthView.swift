import SwiftUI

struct AuthView: View {
    @Environment(AuthManager.self) var auth
    @Environment(LanguageManager.self) var lang

    private let theme = CatThemes.defaultTheme

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.bg, theme.card],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                CatAvatar(theme: theme, size: 110, showRing: true)
                    .shadow(color: theme.deep.opacity(0.25), radius: 16, x: 0, y: 8)

                Spacer().frame(height: 28)

                Text(lang.loc("auth.welcome"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(lang.loc("auth.subtitle"))
                    .font(.subheadline).foregroundColor(.secondary).padding(.top, 6)

                Spacer().frame(height: 48)

                Text(lang.loc("auth.note"))
                    .font(.caption).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)

                Spacer().frame(height: 24)

                // Google Sign In
                Button {
                    Task { await auth.signInWithGoogle() }
                } label: {
                    HStack(spacing: 12) {
                        if auth.isLoading && auth.loadingProvider == .google {
                            ProgressView().tint(.white)
                        } else {
                            ZStack {
                                Circle().fill(.white).frame(width: 28, height: 28)
                                Text("G").font(.system(size: 16, weight: .bold))
                                    .foregroundColor(Color(red:0.26,green:0.52,blue:0.96))
                            }
                        }
                        Text(lang.loc("auth.google")).fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(Color(red:0.26,green:0.52,blue:0.96))
                    .foregroundColor(.white).cornerRadius(16)
                    .shadow(color: Color(red:0.26,green:0.52,blue:0.96).opacity(0.35), radius: 10, x: 0, y: 5)
                }
                .disabled(auth.isLoading)
                .padding(.horizontal, 32)

                // Divider "or"
                HStack {
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                    Text(lang.loc("auth.or"))
                        .font(.caption).foregroundColor(.secondary).padding(.horizontal, 12)
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                }
                .padding(.horizontal, 32).padding(.vertical, 14)

                // Apple Sign In
                Button {
                    Task { await auth.signInWithApple() }
                } label: {
                    HStack(spacing: 12) {
                        if auth.isLoading && auth.loadingProvider == .apple {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 18, weight: .medium))
                        }
                        Text(lang.loc("auth.apple")).fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(Color.black)
                    .foregroundColor(.white).cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 5)
                }
                .disabled(auth.isLoading)
                .padding(.horizontal, 32)

                if let error = auth.errorMessage {
                    Text(error).font(.caption).foregroundColor(.red).padding(.top, 8).padding(.horizontal, 32)
                }

                Spacer().frame(height: 20)

                Button(lang.loc("auth.skip")) {
                    withAnimation { auth.isLoggedIn = true }
                }
                .font(.subheadline).foregroundColor(.secondary).padding(.bottom, 4)

                Spacer()
                Text("🐾  KittyScan").font(.caption2).foregroundColor(.secondary.opacity(0.6)).padding(.bottom, 20)
            }
        }
    }
}
