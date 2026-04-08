# Predkt iOS App

A native SwiftUI companion app for the Predkt sports prediction platform. This app connects to the same Supabase database and Express backend as the web version.

## MVP Features

- ✅ **Authentication** — Login/Signup with Supabase Auth
- ✅ **Feed** — View community picks and your daily picks in real-time
- ✅ **Predict** — Browse live matches, select markets, and submit picks
- ✅ **Profile** — View your stats (points, streaks)
- ✅ **Dark theme** — Matches the web app design

## Prerequisites

- **Xcode 14.0+** (with iOS 14+ deployment target)
- **Apple Developer Account** (for TestFlight/App Store distribution)
- CocoaPods or Swift Package Manager

## Setup Instructions

### Step 1: Create Xcode Project

```bash
# Create a new iOS app in Xcode
# File → New → Project → App (iOS)
# Product Name: Predkt
# Bundle Identifier: com.yourname.predkt
# Ensure SwiftUI is selected as the interface
```

### Step 2: Add Supabase Swift SDK

In Xcode:

1. Go to **File → Add Packages**
2. Paste: `https://github.com/supabase-community/supabase-swift.git`
3. Select version: **Up to Next Major** (1.0.0 or later)
4. Click **Add to Project**
5. Ensure **Predkt** target is selected
6. Click **Add Package**

### Step 3: Copy Swift Files

1. In Xcode, right-click the project navigator (left sidebar)
2. Select **Add Files to "Predkt"**
3. Navigate to `ios/Predkt/` folder
4. Select all files and folders (Models/, Managers/, ViewModels/, Views/, PredktApp.swift, ContentView.swift)
5. Ensure **Copy items if needed** is checked
6. Click **Add**

Your project structure should look like:

```
Predkt/
├── PredktApp.swift
├── ContentView.swift
├── Models/
│   ├── Pick.swift
│   ├── UserProfile.swift
│   └── Match.swift
├── Managers/
│   ├── SupabaseManager.swift
│   └── APIManager.swift
├── ViewModels/
│   ├── AuthViewModel.swift
│   ├── FeedViewModel.swift
│   └── PredictViewModel.swift
└── Views/
    ├── Auth/
    │   └── AuthView.swift
    ├── Feed/
    │   └── FeedView.swift
    └── Predict/
        └── PredictView.swift
└── MainTabView.swift
```

### Step 4: Update Bundle ID & Sign

1. Select **Predkt** project in navigator
2. Select **Predkt** target
3. Go to **Signing & Capabilities**
4. Set **Bundle Identifier** to your unique ID (e.g., `com.yourname.predkt`)
5. Select your **Team** for signing
6. Ensure **Automatically manage signing** is checked

### Step 5: Build & Run

1. Select a simulator or connected device
2. Press **Cmd + B** to build
3. Press **Cmd + R** to run

## API Connections

The app connects to:

- **Supabase**: `https://iffpxhemvquxgstcmnff.supabase.co`
  - Auth (login/signup)
  - Database (picks, profiles, follows)
- **Backend API**: `https://api.predkt.app`
  - `/api/live` — Live match data
  - `/api/signup` — Account creation
  - `/api/verify-email` — Email verification

All credentials are hardcoded in `SupabaseManager.swift` and match the web app's .env.local.

## Features & Architecture

### Authentication Flow

1. User opens app → **ContentView** checks `supabaseManager.user`
2. If logged out → **AuthView** (login/signup form)
3. If logged in → **MainTabView** (Feed / Predict / Profile tabs)

### Feed

- Loads community picks and user's today's picks in **parallel** (optimized for slow networks)
- Updates with refresh button
- Shows result badges (✓ Correct, ✗ Wrong, ⏱ Pending)

### Predict

- Fetches live matches from `/api/live`
- Displays markets (Home Win, Away Win, Draw, Over/Under Goals)
- Submits picks to Supabase `picks` table
- Points formula matches web app exactly: `WIN = max(1, round(4 × odds × (conf/100)))`

### Profile

- Shows user stats (total points, weekly points, streaks)
- Logout button

## Troubleshooting

### Build Errors

- **Module not found: Supabase** → Ensure you added the Swift Package correctly
- **Missing files** → Double-check all files are in the project navigator with blue folder icons

### Runtime Errors

- **"Invalid token"** → Supabase keys may have expired; verify in SupabaseManager.swift
- **Blank feed** → Check your internet connection and Supabase database rules (RLS policies)

### Testing

```swift
// Quick login test:
Email: (use an existing account you set up in Supabase)
Password: (your password)
```

## Distribution (TestFlight)

1. Go to your Apple Developer account → App Store Connect
2. Create a new app (Bundle ID must match)
3. In Xcode: **Product → Archive**
4. In Organizer: **Distribute App** → TestFlight
5. Select compliance settings and submit
6. Invite testers via TestFlight link

## Next Steps

Future features to add:

- [ ] Leaderboard screen
- [ ] Leagues screen
- [ ] Push notifications for match reminders
- [ ] Dark/Light theme toggle
- [ ] Offline mode (cache picks)
- [ ] Watchlist / Favorited matches
- [ ] Admin panel (resolve & settle picks)

## Support

For issues with the Swift code, refer to:
- [Supabase Swift Docs](https://github.com/supabase-community/supabase-swift)
- [SwiftUI Docs](https://developer.apple.com/tutorials/swiftui)
- [Apple App Store Connect Help](https://help.apple.com/app-store-connect/)

---

Built with ❤️ using SwiftUI + Supabase
