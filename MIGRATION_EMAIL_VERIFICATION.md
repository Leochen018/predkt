# Email Verification Feature - Database Migration

## Overview
This migration adds email verification functionality to the app. After 3 days (72 hours), guest users must create an account with email. They will then receive a verification email and can optionally verify to unlock leaderboard and league features.

## Database Changes

### 1. Add columns to `profiles` table

Run the following SQL in your Supabase SQL editor:

```sql
-- Add email verification columns to profiles table
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS email_verified boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS verification_token text,
ADD COLUMN IF NOT EXISTS token_expires_at timestamp with time zone;

-- Create an index for faster token lookups (optional but recommended)
CREATE INDEX IF NOT EXISTS idx_profiles_verification_token 
ON profiles(verification_token) 
WHERE verification_token IS NOT NULL;
```

## Key Features

1. **New Auth Screens**
   - `verify-email-sent`: Shown after user signs up or upgrades, prompts them to check email
   - `email-verified`: Shown when email verification is successful

2. **Verification Flow**
   - User creates account or upgrades from guest
   - Receives email with verification link
   - Clicks link to verify (token expires in 24 hours)
   - Gets access to leaderboard and leagues

3. **Access Control**
   - Leaderboard: Shows banner prompting email verification if not verified
   - Leagues: Users cannot create or join leagues without verified email
   - Error messages guide users to verify

4. **API Endpoints**
   - `POST /api/send-verification-email`: Sends verification email
   - `POST /api/verify-email`: Verifies email token

## Authentication Flow

### Signup (New Account)
1. User fills in username, email, password
2. Account created with `email_verified = false`
3. Verification token generated and sent via email
4. User sees "verify-email-sent" screen
5. User clicks link in email
6. Email verified, gains full access

### Upgrade (Convert Guest to Full Account)
1. Guest user after 72 hours sees "Save progress" prompt
2. User adds email and password
3. Account upgraded with `email_verified = false`
4. Verification token generated and sent via email
5. User sees "verify-email-sent" screen
6. User clicks link in email
7. Email verified, gains full access

## Email Template

The verification email should contain a link like:
```
https://yourapp.com/verify?token=TOKEN&userId=USER_ID
```

Replace `TOKEN` and `USER_ID` with actual values. The app will automatically handle the verification when the user clicks the link.

## Notes

- Verification tokens expire after 24 hours
- If a user loses the email, they can attempt to sign up again (the new request will create a new token)
- The app currently logs verification URLs to console (for development)
- For production, integrate with an email service (Resend, SendGrid, etc.) to send actual emails

## Testing

To test locally:
1. In development, verification URLs are logged to server console
2. Copy the verification URL and visit it in the app
3. You should see the "email-verified" screen
4. After logging in, the user's `email_verified` status will be true
