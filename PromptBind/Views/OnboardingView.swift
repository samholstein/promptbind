import SwiftUI

struct OnboardingView: View {
    // A callback to notify the parent view that onboarding is complete.
    var onComplete: () -> Void
    
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to PromptBind")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Replaced TabView with a custom paging view for macOS compatibility.
            // The .id() modifier helps SwiftUI know which view to transition from/to.
            TabView(selection: $selectedTab) {
                OnboardingPageView(
                    imageName: "keyboard.fill",
                    title: "Supercharge Your Typing",
                    description: "PromptBind is a powerful text-expansion app. Type a short trigger, and it will be replaced with your custom text automatically."
                )
                .tag(0)
                
                OnboardingPageView(
                    imageName: "wand.and.stars",
                    title: "Create Your First Prompt",
                    description: "After setup, you'll create your first text expansion prompt. Think of something you type often - like your email signature or a common response."
                )
                .tag(1)

                OnboardingPageView(
                    imageName: "lock.shield.fill",
                    title: "Accessibility Permission",
                    description: "To monitor your typing system-wide, PromptBind needs Accessibility permissions. We will ask for this permission after you close this welcome screen."
                )
                .tag(2)
            }
            .id(selectedTab)
            .transition(.opacity.animation(.easeInOut))
            .frame(height: 250)
            
            HStack {
                if selectedTab > 0 {
                    Button("Back") {
                        withAnimation {
                            selectedTab -= 1
                        }
                    }
                }
                
                Spacer()
                
                if selectedTab < 2 {
                    Button("Next") {
                        withAnimation {
                            selectedTab += 1
                        }
                    }
                } else {
                    Button("Get Started") {
                        onComplete()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(30)
        .frame(width: 500, height: 400)
    }
}

struct OnboardingPageView: View {
    let imageName: String
    let title: String
    let description: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: imageName)
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(onComplete: {})
    }
}