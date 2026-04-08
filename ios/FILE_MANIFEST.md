# iOS App File Manifest

All files ready to import into your Xcode project.

## Location
```
/Users/leochen/Downloads/pythonTestSVDDissertation/predkt/ios/Predkt/
```

## File Structure (16 Swift + 2 Docs)

### Entry Point
- **PredktApp.swift** — @main app delegate, injects SupabaseManager to environment
- **ContentView.swift** — Router between AuthView and MainTabView based on auth state

### Models (3 files)
- **Models/Pick.swift** — Codable struct for picks, includes Profile nested struct
- **Models/UserProfile.swift** — Codable struct for user profile data
- **Models/Match.swift** — Match data model + LiveMatchResponse for API parsing

### Managers (2 files)
- **Managers/SupabaseManager.swift** — Singleton with Supabase client, auth methods, and database queries
  - `login(email, password)`
  - `signup(email, password, username)` — calls backend API
  - `fetchFeed()` — loads community picks
  - `fetchMyPicks()` — loads user's today picks
  - `createPick(...)` — inserts pick to picks table
  - `fetchUserProfile()` — loads user stats
- **Managers/APIManager.swift** — URLSession wrapper for backend calls
  - `fetchLiveMatches()` — GET /api/live
  - `verifyEmail(userId, token)` — POST /api/verify-email

### ViewModels (3 files)
- **ViewModels/AuthViewModel.swift** — @MainActor ObservableObject
  - `login()` — authenticate with Supabase
  - `signup()` — create account via backend
  - `logout()` — sign out
  - Properties: email, password, username, isLoading, errorMessage, isSignupMode
- **ViewModels/FeedViewModel.swift** — @MainActor ObservableObject
  - `load()` — parallel fetch of feed, myPicks, profile
  - `refresh()` — reload data
  - Properties: feedPicks, myPicks, userProfile, isLoading
- **ViewModels/PredictViewModel.swift** — @MainActor ObservableObject
  - `loadMatches()` — fetch live matches from API
  - `getMarkets(for:)` — return hardcoded markets for a match
  - `submitPick(...)` — insert pick to database
  - Properties: matches, confidence, selectedMatch, isSubmitting

### Views (6 files organized by feature)
- **Views/Auth/AuthView.swift** — Dark-themed login/signup form
  - Toggle between login and signup modes
  - Email + password required, username for signup
  - Error message display
- **Views/Feed/FeedView.swift** — Two-section scrollable feed
  - "Today's Picks" section (user's own picks)
  - "Community Feed" section (all users' latest picks)
  - Refresh button + loading state
  - Shows result badges and match info
- **Views/Predict/PredictView.swift** — Match list + market sheet
  - Scrollable list of live matches from API
  - Tap match → MarketSheetView (bottom sheet)
  - Select market, adjust confidence slider (1-100)
  - Submit button to create pick
  - Live status badge and score display
- **Views/MainTabView.swift** — Tab bar navigation + ProfileView
  - TabView with 3 tabs: Feed, Predict, Profile
  - ProfileView shows username, email, stats (total points, streaks)
  - Logout button in profile

## Xcode Project Setup

1. Create new iOS app in Xcode (name: "Predkt")
2. Add Swift Package: `https://github.com/supabase-community/supabase-swift.git`
3. Add all files from `ios/Predkt/` folder to project
4. Update Bundle ID and select Team for signing
5. Build and run

## Code Highlights

### Parallel Data Loading
```swift
// FeedViewModel - loads feed, picks, profile simultaneously
async let feedTask = supabaseManager.fetchFeed()
async let myPicksTask = supabaseManager.fetchMyPicks()
async let profileTask = supabaseManager.fetchUserProfile()
let (feed, myPicks, profile) = try await (feedTask, myPicksTask, profileTask)
```

### Points Calculation (Mirrors Web App)
```swift
let confRatio = Double(confidence) / 100.0
let basePoints = Int(4.0 * market.odds * confRatio)
let finalWin = max(1, basePoints)
let finalLoss = max(1, Int(4.0 * market.odds * confRatio * 0.5))
```

### Auth Gate Router
```swift
// ContentView routes based on supabaseManager.user
if supabaseManager.user != nil {
    MainTabView()
} else {
    AuthView()
}
```

## Dependencies

- **Supabase** (Swift SDK) — Auth + PostgreSQL client
  - Add via Swift Package Manager
  - URL: `https://github.com/supabase-community/supabase-swift`
  - Version: 1.0.0+

No other external dependencies (uses standard Foundation, SwiftUI, URLSession).

## Configuration

All hardcoded in SupabaseManager.swift:

```swift
private let supabaseURL = "https://iffpxhemvquxgstcmnff.supabase.co"
private let supabaseKey = "eyJhbGc..." // Public anon key
static let baseURL = "https://api.predkt.app"
```

These match the web app's environment variables and are safe to hardcode (public keys only).

## Testing Checklist

- [ ] Build succeeds without errors
- [ ] App launches and shows login screen
- [ ] Login with valid Supabase account works
- [ ] Feed displays your picks and community picks
- [ ] Predict tab shows live matches
- [ ] Can select match → market → set confidence → submit pick
- [ ] Pick appears in feed after submission
- [ ] Profile shows correct stats
- [ ] Logout works and returns to login

## File Count Summary

```
Total Files: 18
├── Swift Files: 16
│   ├── Root: 2 (PredktApp, ContentView)
│   ├── Models: 3 (Pick, UserProfile, Match)
│   ├── Managers: 2 (SupabaseManager, APIManager)
│   ├── ViewModels: 3 (AuthViewModel, FeedViewModel, PredictViewModel)
│   └── Views: 6 (AuthView, FeedView, PredictView, MainTabView, PickCardView, StatCard)
└── Documentation: 2 (README.md, SETUP.md)
```

## Next Steps

1. **Immediate**: Follow SETUP.md to get the app running
2. **Testing**: Test login, feed, predict, and logout flows
3. **Deployment**: Archive and submit to TestFlight
4. **Future Enhancements**: 
   - Leaderboard screen
   - Notifications
   - Offline caching
   - Admin panel

---

**Ready to build!** 🚀
