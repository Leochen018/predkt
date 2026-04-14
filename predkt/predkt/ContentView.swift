import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var supabaseManager: SupabaseManager
    @State private var isLaunching = true
    @State private var logoPulse = false

    var body: some View {
        Group {
            if isLaunching {
                splashView
            } else if supabaseManager.session != nil {
                MainTabView()
                    .transition(.opacity)
            } else {
                AuthView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isLaunching)
        .animation(.default, value: supabaseManager.session == nil)
        .task {
            await runStartup()
        }
    }

    // MARK: - Splash screen

    private var splashView: some View {
        ZStack {
            Color(red: 0.031, green: 0.035, blue: 0.055).ignoresSafeArea()

            VStack(spacing: 16) {
                Image("PredktLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(
                        color: Color(red: 0.784, green: 1.0, blue: 0.337).opacity(0.4),
                        radius: 24, x: 0, y: 0
                    )
                    .scaleEffect(logoPulse ? 1.04 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                        value: logoPulse
                    )

                Text("Predkt")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .kerning(-1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            logoPulse = true
           
        }
    }

    // MARK: - Startup sequence

    private func runStartup() async {
        let startTime = Date()

        // Fire notification check in background — don't wait for it
        Task { await NotificationManager.shared.checkStatus() }

        // Wait for matches — uses disk cache so near instant after first launch
        _ = try? await APIManager.fetchAllMatches()

        let elapsed   = Date().timeIntervalSince(startTime)
        let remaining = max(0, 1.0 - elapsed)
        if remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }

        withAnimation(.easeInOut(duration: 0.4)) {
            isLaunching = false
        }
    }
}
