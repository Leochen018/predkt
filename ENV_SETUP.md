# Environment Variables Setup - Predkt

## Overview

You need to configure environment variables in two places:
1. **Backend** (`server/.env`) - Running on Railway
2. **Frontend** (`files/.env.local`) - Running on Vercel or Railway

## Backend Configuration (server/.env)

Create or update `server/.env`:

```bash
# Supabase (Database & Auth)
NEXT_PUBLIC_SUPABASE_URL=https://iffpxhemvquxgstcmnff.supabase.co
SUPABASE_SERVICE_KEY=sb_secret_LQtMyKItLBaI9nhWMPxg8g_doGc9FJU

# API Football (Match & Odds Data)
API_FOOTBALL_KEY=2baabc52a043795f48d8b84ba9f5197a

# Email Service (Resend)
RESEND_API_KEY=re_xxxxxxxxxxxxxxxxxxxxx  # Get from https://resend.com/api-keys

# App Configuration
NEXT_PUBLIC_APP_URL=https://predkt.app
PORT=3001
```

## Frontend Configuration (files/.env.local)

Create or update `files/.env.local`:

```bash
# Backend API URL
NEXT_PUBLIC_API_BASE_URL=https://api.predkt.app

# App URL (for email verification links)
NEXT_PUBLIC_APP_URL=https://predkt.app
```

## Railway Dashboard Setup

When deploying to Railway:

1. Go to your service settings
2. Click "Variables" tab
3. Add each variable from `server/.env`
4. **Do NOT commit `.env` files to GitHub** (they're in .gitignore)

### Variables to Add to Railway:
```
NEXT_PUBLIC_SUPABASE_URL
SUPABASE_SERVICE_KEY
API_FOOTBALL_KEY
RESEND_API_KEY
NEXT_PUBLIC_APP_URL
PORT
```

## Getting Your API Key Values

### Supabase
- Already have: `NEXT_PUBLIC_SUPABASE_URL` and `SUPABASE_SERVICE_KEY`
- Check your Supabase project settings if needed

### API Football
- Already have: `API_FOOTBALL_KEY=2baabc52a043795f48d8b84ba9f5197a`

### Resend (Email Service)
1. Go to https://resend.com/api-keys
2. Create a new API key
3. Copy and paste it as `RESEND_API_KEY`

### NEXT_PUBLIC_APP_URL
For production:
```
NEXT_PUBLIC_APP_URL=https://predkt.app
```

For development:
```
NEXT_PUBLIC_APP_URL=http://localhost:3000
```

## Email Configuration Steps

### 1. Add Domain to Resend
1. Go to https://resend.com/domains
2. Click "Add Domain"
3. Enter: `predkt.app`
4. Add the DNS records to your domain

### 2. Verify Domain
1. Wait for DNS propagation (up to 24 hours)
2. Return to Resend Domains
3. Click "Verify"

### 3. Test Email Sending
- Sign up on your app with a test email
- Check inbox for verification email from `noreply@predkt.app`
- Click verification link to confirm it works

## Local Development

For testing locally without Railway:

### server/.env
```bash
NEXT_PUBLIC_SUPABASE_URL=https://iffpxhemvquxgstcmnff.supabase.co
SUPABASE_SERVICE_KEY=sb_secret_LQtMyKItLBaI9nhWMPxg8g_doGc9FJU
API_FOOTBALL_KEY=2baabc52a043795f48d8b84ba9f5197a
RESEND_API_KEY=re_xxxxxxxxxxxxxxxxxxxxx
NEXT_PUBLIC_APP_URL=http://localhost:3000
PORT=3001
```

### files/.env.local
```bash
NEXT_PUBLIC_API_BASE_URL=http://localhost:3001
NEXT_PUBLIC_APP_URL=http://localhost:3000
```

### Run Locally
```bash
# Terminal 1 - Backend
cd server
npm run dev

# Terminal 2 - Frontend
cd files
npm run dev
```

## Production Deployment (Railway + Vercel)

### Backend (Railway)
Copy all variables from `server/.env` to Railway dashboard

### Frontend (Vercel)
1. In Vercel project settings → Environment Variables
2. Add:
   - `NEXT_PUBLIC_API_BASE_URL=https://api.predkt.app`
   - `NEXT_PUBLIC_APP_URL=https://predkt.app`

## Security Notes

⚠️ **Important:**
- Never commit `.env` files to GitHub
- Never share API keys publicly
- Rotate API keys periodically
- Use `.env.local` for development (in `.gitignore`)
- Use Railway/Vercel dashboard for production variables

## Troubleshooting

### API calls failing
- Check `NEXT_PUBLIC_API_BASE_URL` is correct
- Verify backend is deployed and running
- Check browser console for errors

### Emails not sending
- Verify `RESEND_API_KEY` is correct
- Check Resend domain is verified
- Check `from: "noreply@predkt.app"` in code
- Wait for DNS to propagate

### App loading blank
- Check `NEXT_PUBLIC_APP_URL` is correct
- Check environment variables are set
- Look at browser console errors

## Quick Reference

| Variable | Development | Production |
|----------|-------------|-----------|
| NEXT_PUBLIC_APP_URL | http://localhost:3000 | https://predkt.app |
| NEXT_PUBLIC_API_BASE_URL | http://localhost:3001 | https://api.predkt.app |
| RESEND_API_KEY | Your test key | Your production key |

