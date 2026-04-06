# Railway Frontend Deployment - Step-by-Step

## Prerequisites
- ✅ Backend already deployed on Railway
- ✅ Domain: predkt.app
- ✅ Environment variables ready

## Step 1: Get Your Backend URL

1. Go to your Railway dashboard
2. Click on your **backend service** (the `server` one)
3. Look for "Public URL" or "Railway URL"
4. Copy it (looks like: `https://xxx-production.railway.app`)
5. Save it - you'll need it in a few minutes

## Step 2: Create Frontend Service in Railway

### 2.1 In Your Railway Project
1. Go to your Railway project dashboard
2. Click **"New Service"** button
3. Select **"GitHub Repo"**
4. Select your repository: `pythonTestSVDDissertation/predkt`

### 2.2 Configure the Service
1. In the new service dialog:
   - **Root Directory**: `files`
   - **Build Command**: `npm run build`
   - **Start Command**: `npm start`

2. Click **"Create Service"**
3. Railway will auto-detect Node.js and Next.js

## Step 3: Add Environment Variables

1. In your **frontend service**, click **"Variables"** tab
2. Click **"Add Variable"** and add these:

| Key | Value |
|-----|-------|
| `NEXT_PUBLIC_API_BASE_URL` | Your backend URL (from Step 1) |
| `NEXT_PUBLIC_APP_URL` | `https://predkt.app` |

**Example:**
```
NEXT_PUBLIC_API_BASE_URL=https://predkt-prod-xyz123.railway.app
NEXT_PUBLIC_APP_URL=https://predkt.app
```

3. Click **"Add"** for each variable
4. Railway will auto-redeploy with new variables

## Step 4: Watch Deployment

1. Click the **"Deployments"** tab
2. Watch the build progress
3. You should see:
   - `npm install` running
   - `npm run build` running
   - Build succeeding
   - Service starting

4. Once complete, you'll see a **green checkmark** and a URL like:
   - `https://frontend-prod-xyz.railway.app`

## Step 5: Add Custom Domain

### 5.1 In Railway
1. In your **frontend service**, click **"Settings"** tab
2. Scroll down to **"Domains"**
3. Click **"Add Domain"**
4. Enter: `predkt.app`
5. Railway will show you a **CNAME record**
6. Copy it

### 5.2 In Your Domain Registrar
1. Go to your domain registrar (GoDaddy, Namecheap, etc.)
2. Find "DNS Management" or "DNS Settings"
3. Look for `predkt.app` domain
4. Add/Update the CNAME record:
   - **Name**: `@` or leave blank
   - **Type**: `CNAME`
   - **Value**: Paste what Railway gave you
5. Save changes

### 5.3 Wait for DNS
- DNS can take 5 minutes to 24 hours
- Check status at: https://dnschecker.org
- Once verified, Railway will show a ✅ next to your domain

## Step 6: Test Everything

### 6.1 Check Frontend
1. Go to `https://predkt.app`
2. Page should load (might see Railway's default if DNS not propagated yet)
3. Once DNS works, you'll see your Predkt app

### 6.2 Test Email Verification
1. Click "Create account"
2. Sign up with a test email
3. Check inbox for `noreply@predkt.app` email
4. Click verification link
5. Should see success message
6. Verify and log in
7. Access leaderboard and leagues

## Troubleshooting

### Build Failed
1. Check build logs in Railway
2. Common issues:
   - Missing npm packages: run `cd files && npm install`
   - Node version: ensure Node 20+ in `package.json`
   - Environment variables: make sure they're set before deploy

### Site shows Railway default page
- DNS not propagated yet
- Check: https://dnschecker.org
- Wait up to 24 hours
- Meanwhile, use the Railway URL to test

### API calls failing (network errors)
1. Check `NEXT_PUBLIC_API_BASE_URL` is correct
2. Verify backend service is running
3. Check Railway backend service logs
4. Make sure there's no typo in the URL

### Emails not sending
1. Check backend service logs for errors
2. Verify `RESEND_API_KEY` in backend service
3. Check Resend domain is verified: https://resend.com/domains
4. Check backend `NEXT_PUBLIC_APP_URL` is set to `https://predkt.app`

### App loads blank
1. Check browser console (F12) for errors
2. Check Railway logs for errors
3. Verify environment variables are set
4. Try hard refresh: Ctrl+Shift+R (Windows) or Cmd+Shift+R (Mac)

## Quick Reference

### Frontend Service Environment Variables
```
NEXT_PUBLIC_API_BASE_URL=https://your-backend-url.railway.app
NEXT_PUBLIC_APP_URL=https://predkt.app
```

### Railway URL Format
- Backend: `https://xxx-production.railway.app`
- Frontend: `https://frontend-xxx-production.railway.app`

### DNS Record (After step 5.2)
- Type: `CNAME`
- Name: `@` (for root domain) or `www`
- Value: Railway's CNAME value

## Monitoring

### Check Deployment Status
1. Go to frontend service → Deployments
2. Green checkmark = Success
3. Red X = Failed (check logs)

### Check Logs
1. Go to frontend service → Logs
2. Look for:
   - `ready - started server` = Good
   - Errors = Check what went wrong

### Monitor Traffic
1. Go to frontend service → Monitoring
2. See requests, response times, errors

## Next Steps After Deployment

1. ✅ Test email verification fully
2. ✅ Create test accounts
3. ✅ Test leaderboard access
4. ✅ Test league creation/joining
5. Monitor logs for any errors
6. Share your app: `https://predkt.app`

## Important Notes

- Railway frontend builds automatically when you push to GitHub
- Both frontend and backend are in same Railway project
- Environment variables are stored securely in Railway
- Deployments are automatic when you push to main branch
- Check Railway dashboard for any errors or warnings

---

**You're almost there! 🚀**

Once DNS propagates and tests pass, your app is live!

