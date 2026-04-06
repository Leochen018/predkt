# Predkt Deployment Checklist

## ✅ What's Already Done

- [x] Email verification feature implemented
- [x] Resend integration added to backend
- [x] Code updated to use domain: `noreply@predkt.app`
- [x] Environment variable templates created

## 📋 Your Deployment Checklist

### Phase 1: Resend Domain Setup (1-24 hours)

- [ ] Go to https://resend.com and sign up
- [ ] Get your API key from https://resend.com/api-keys
- [ ] Go to https://resend.com/domains
- [ ] Click "Add Domain" and enter: `predkt.app`
- [ ] Copy the DNS records Resend provides
- [ ] Go to your domain registrar (GoDaddy, Namecheap, etc.)
- [ ] Add the DNS records for predkt.app
- [ ] Return to Resend and click "Verify"
- [ ] Wait for DNS to propagate (up to 24 hours)

### Phase 2: Railway Backend Setup (30 minutes)

- [ ] Go to https://railway.app and sign up
- [ ] Create a new project
- [ ] Connect your GitHub repository
- [ ] Create a new service with root directory: `server`
- [ ] Configure build command: `npm install`
- [ ] Configure start command: `npm start`
- [ ] Add environment variables to Railway:
  - [ ] `NEXT_PUBLIC_SUPABASE_URL`
  - [ ] `SUPABASE_SERVICE_KEY`
  - [ ] `API_FOOTBALL_KEY`
  - [ ] `RESEND_API_KEY` (from Resend)
  - [ ] `NEXT_PUBLIC_APP_URL=https://predkt.app`
  - [ ] `PORT=3001`
- [ ] Click "Deploy"
- [ ] Wait for deployment to complete
- [ ] Copy the public URL from Railway
- [ ] Update `NEXT_PUBLIC_API_BASE_URL` in frontend `.env`

### Phase 3: Database Migration (5 minutes)

- [ ] Go to your Supabase dashboard
- [ ] Open SQL Editor
- [ ] Run the migration SQL (see MIGRATION_EMAIL_VERIFICATION.md):
  ```sql
  ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS email_verified boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS verification_token text,
  ADD COLUMN IF NOT EXISTS token_expires_at timestamp with time zone;

  CREATE INDEX IF NOT EXISTS idx_profiles_verification_token 
  ON profiles(verification_token) 
  WHERE verification_token IS NOT NULL;
  ```

### Phase 4: Frontend Deployment - Option A: Vercel (Recommended)

- [ ] Go to https://vercel.com and sign up
- [ ] Click "New Project"
- [ ] Select your GitHub repository
- [ ] Set root directory: `files`
- [ ] Add environment variables:
  - [ ] `NEXT_PUBLIC_API_BASE_URL=https://api.predkt.app` (or your Railway URL)
  - [ ] `NEXT_PUBLIC_APP_URL=https://predkt.app`
- [ ] Deploy
- [ ] Go to Domains settings
- [ ] Add custom domain: `predkt.app`
- [ ] Add CNAME records that Vercel provides to your domain registrar

### Phase 4: Frontend Deployment - Option B: Railway

- [ ] Create new service in Railway (same project as backend)
- [ ] Root directory: `files`
- [ ] Build command: `npm run build`
- [ ] Start command: `npm start`
- [ ] Add environment variables:
  - [ ] `NEXT_PUBLIC_API_BASE_URL=https://api.predkt.app`
  - [ ] `NEXT_PUBLIC_APP_URL=https://predkt.app`
- [ ] Deploy
- [ ] Add custom domain: `predkt.app` (Railway will provide CNAME)

### Phase 5: Domain Setup (30 minutes - 24 hours)

- [ ] Go to your domain registrar
- [ ] Update CNAME records for:
  - [ ] API subdomain (if using Railway subdomain)
  - [ ] Main domain (if using Vercel/Railway for frontend)
- [ ] Wait for DNS to propagate
- [ ] Test that URLs are accessible:
  - [ ] https://predkt.app (frontend)
  - [ ] https://api.predkt.app (backend) or Railway URL

### Phase 6: Testing (15 minutes)

- [ ] Go to https://predkt.app in your browser
- [ ] Sign up with a test email address
- [ ] Check inbox for verification email from `noreply@predkt.app`
- [ ] Verify it contains:
  - [ ] "Verify Email" button
  - [ ] Clickable link
  - [ ] 24-hour expiration notice
- [ ] Click the verification link
- [ ] Confirm success message shows
- [ ] Log in with your test account
- [ ] Verify email is marked as verified
- [ ] Test leaderboard access
- [ ] Test league creation/joining

### Phase 7: Production Monitoring

- [ ] Set up error tracking (optional but recommended)
- [ ] Monitor Railway logs for errors
- [ ] Monitor Resend dashboard for email delivery
- [ ] Set up alerts for failed emails
- [ ] Keep API keys secure

## 📝 Important Files to Reference

- **RAILWAY_DEPLOYMENT.md** - Detailed Railway setup instructions
- **ENV_SETUP.md** - Environment variable configuration
- **MIGRATION_EMAIL_VERIFICATION.md** - Database migration SQL
- **RESEND_SETUP.md** - Resend configuration guide
- **EMAIL_SETUP.md** - General email service setup

## 🚀 Quick Start Command Reference

### Get Resend API Key
```
https://resend.com/api-keys
```

### Deploy Backend
```bash
# Push code to GitHub
git push origin main

# In Railway:
# 1. New Project → New Service → GitHub Repo
# 2. Set root directory to: server
# 3. Add environment variables
# 4. Deploy
```

### Deploy Frontend
```bash
# In Vercel or Railway:
# 1. New Project → GitHub Repo
# 2. Set root directory to: files
# 3. Add environment variables
# 4. Deploy
```

## 💡 Pro Tips

1. **Test locally first**: Run both server and frontend locally with your real Resend key
2. **Check logs**: Railway logs are your friend for debugging
3. **DNS patience**: DNS changes take up to 24 hours - don't panic
4. **Start simple**: Get backend + email working before adding frontend domain
5. **Use Resend dashboard**: Check email delivery status there

## 🆘 Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| Emails not arriving | Check Resend domain is verified, check RESEND_API_KEY |
| Verification link broken | Verify NEXT_PUBLIC_APP_URL is set correctly |
| Domain not working | Check DNS propagation at dnschecker.org |
| Backend 502 errors | Check Railway logs, verify environment variables |
| Frontend blank | Check browser console, verify API_BASE_URL |

## 📞 Support Resources

- **Railway Docs**: https://docs.railway.app
- **Resend Docs**: https://resend.com/docs
- **Vercel Docs**: https://vercel.com/docs
- **DNS Checker**: https://dnschecker.org

---

**Estimated Total Time**: 2-4 hours (mostly DNS propagation waiting)

**Good luck! 🚀**

