# Quick Setup Guide

## 1 Minute Checklist

- [ ] Open Xcode → **File → New → Project**
- [ ] Select **iOS → App**, name: `Predkt`
- [ ] **File → Add Packages** → paste `https://github.com/supabase-community/supabase-swift.git`
- [ ] Right-click project → **Add Files to Predkt** → select all from `ios/Predkt/`
- [ ] Update **Bundle ID** (Settings → Signing & Capabilities)
- [ ] Select your **Team**
- [ ] **Cmd + R** to run

## Files You'll Add

```
Models/
  └── Pick.swift                    (Pick & Profile data model)
  └── UserProfile.swift             (User profile data model)
  └── Match.swift                   (Match & fixture data model)

Managers/
  └── SupabaseManager.swift         (Singleton for Supabase client)
  └── APIManager.swift              (Backend HTTP calls)

ViewModels/
  └── AuthViewModel.swift           (@MainActor, handles login/signup)
  └── FeedViewModel.swift           (@MainActor, loads picks in parallel)
  └── PredictViewModel.swift        (@MainActor, match & pick submission)

Views/
  └── Auth/
      └── AuthView.swift            (Login/Signup screen)
  └── Feed/
      └── FeedView.swift            (Community + Today's picks)
  └── Predict/
      └── PredictView.swift         (Match list & market selection)
  
  └── MainTabView.swift             (3-tab navigation + Profile)

Root/
  └── PredktApp.swift               (@main entry point)
  └── ContentView.swift             (Auth gate router)
```

## What the App Does

### Login Screen
- Email + Password login with Supabase
- Signup creates account via backend API
- Session persists via Supabase keychain storage

### Feed Tab
- Shows community picks (all users)
- Shows your picks from today
- Loads both in parallel (fast even on slow networks)
- Shows result badges: ✓ Correct (green), ✗ Wrong (red), ⏱ Pending (gray)

### Predict Tab
- Browse live matches from `/api/live`
- Tap a match → bottom sheet with betting markets
- Select market, adjust confidence slider (1-100%)
- Submit → inserts to Supabase `picks` table

### Profile Tab
- Shows username, email, total points, streaks
- Logout button

## Architecture

```
PredktApp
  ├── @StateObject SupabaseManager (Singleton)
  │   ├── Supabase client (auth + postgrest)
  │   └── Methods: login(), signup(), logout(), fetchFeed(), etc.
  │
  └── ContentView (Auth gate)
      ├── If not logged in → AuthView
      └── If logged in → MainTabView
          ├── FeedView (with @StateObject FeedViewModel)
          ├── PredictView (with @StateObject PredictViewModel)
          └── ProfileView (with @StateObject FeedViewModel for stats)
```

## Deployment

1. **Local Testing**: Select simulator or device, Cmd + R
2. **TestFlight**: Xcode → Product → Archive → Distribute App
3. **App Store**: Same as TestFlight, then submit for review

## Credentials (Already Hardcoded)

- Supabase URL: `https://iffpxhemvquxgstcmnff.supabase.co`
- Supabase Anon Key: (in SupabaseManager.swift)
- Backend URL: `https://api.predkt.app`

⚠️ **NOTE**: These are public keys (safe to hardcode). The backend service key is only on the server.

## Troubleshooting

**Xcode can't find Supabase?**
- Product → Build Phases → Link Binary With Libraries
- Add `Supabase` from the package

**App crashes on launch?**
- Check console for error messages
- Verify internet connection
- Verify Supabase keys in SupabaseManager.swift

**Feed shows no picks?**
- Confirm your web app has created picks
- Check Supabase database → picks table
- Verify RLS policies allow SELECT

---

All set! Open Xcode and start building 🚀
