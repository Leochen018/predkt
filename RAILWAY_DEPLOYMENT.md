# Railway Deployment Guide - Predkt

## Prerequisites

- Domain: **predkt.app** ✓
- Email Service: **Resend**
- Platform: **Railway**
- Backend: **Node.js/Express**
- Frontend: **Next.js**

## Step 1: Configure Resend with Your Domain

### 1.1 Add Domain to Resend
1. Go to https://resend.com/domains
2. Click "Add Domain"
3. Enter: `predkt.app`
4. Resend will give you DNS records to add

### 1.2 Add DNS Records
1. Go to your domain registrar (GoDaddy, Namecheap, etc.)
2. Find DNS management/settings
3. Add the records Resend gives you:
   - Usually includes MX records, SPF, DKIM, DMARC
4. Wait for DNS to propagate (can take up to 24 hours)

### 1.3 Verify Domain in Resend
- Return to https://resend.com/domains
- Click "Verify" on your domain
- Once verified, you can send from `noreply@predkt.app`

### 1.4 Get API Key
- Go to https://resend.com/api-keys
- Create a new API key
- Copy it (you'll need it for Railway)

## Step 2: Deploy Backend to Railway

### 2.1 Create Railway Account
1. Go to https://railway.app
2. Sign up (free tier available)
3. Create a new project

### 2.2 Connect Your Repository
1. In Railway, click "New Project"
2. Select "Deploy from GitHub"
3. Connect your GitHub account if needed
4. Select your repository: `pythonTestSVDDissertation/predkt`

### 2.3 Configure Backend Service
1. In Railway dashboard, click "New Service"
2. Select "GitHub Repo" → your predkt repo
3. Configure:
   - **Root Directory**: `server`
   - **Start Command**: `npm start`

### 2.4 Add Environment Variables
1. In your Railway service settings, go to "Variables"
2. Add these environment variables:

```
NEXT_PUBLIC_SUPABASE_URL=https://iffpxhemvquxgstcmnff.supabase.co
SUPABASE_SERVICE_KEY=sb_secret_LQtMyKItLBaI9nhWMPxg8g_doGc9FJU
API_FOOTBALL_KEY=2baabc52a043795f48d8b84ba9f5197a
RESEND_API_KEY=re_xxxxxxxxxxxxxxxxxx
NEXT_PUBLIC_APP_URL=https://predkt.app
PORT=3001
```

**Important**: Replace `RESEND_API_KEY` with your actual key from Resend.

### 2.5 Deploy
1. Railway will automatically detect `server` folder
2. Click "Deploy"
3. Wait for deployment to complete
4. Copy your backend URL from Railway dashboard (looks like: `https://xxx-production.railway.app`)

### 2.6 Get Backend URL
1. In Railway, go to your service settings
2. Find the "Public URL" or "Railway URL"
3. Save it (example: `https://predkt-prod-xxxx.railway.app`)

## Step 3: Deploy Frontend to Railway or Vercel

### Option A: Deploy Frontend to Railway

1. **Create new service** for frontend in Railway
2. **Configure frontend service**:
   - **Root Directory**: `files`
   - **Build Command**: `npm run build`
   - **Start Command**: `npm start`

3. **Add Environment Variables**:
```
NEXT_PUBLIC_API_BASE_URL=https://your-backend-url.railway.app
NEXT_PUBLIC_APP_URL=https://predkt.app
```

4. **Deploy**

### Option B: Deploy Frontend to Vercel (Recommended for Next.js)

1. Go to https://vercel.com
2. Sign up / Sign in
3. Click "New Project"
4. Select your GitHub repository
5. Configure:
   - **Root Directory**: `files`
   - **Framework**: Next.js

6. **Environment Variables**:
```
NEXT_PUBLIC_API_BASE_URL=https://your-backend-url.railway.app
NEXT_PUBLIC_APP_URL=https://predkt.app
```

7. **Deploy**

## Step 4: Connect Domain to Railway (Backend)

### 4.1 In Railway Dashboard
1. Go to your backend service
2. Find "Public URL" settings
3. Look for "Domain" or "Custom Domain"
4. Click "Add Custom Domain"
5. Enter: `api.predkt.app` (or `api-predkt.app`)

### 4.2 Update DNS Records
Railway will give you a CNAME record:
1. Go to your domain registrar
2. Add the CNAME record Railway provides
3. Point to Railway's domain

### 4.3 Wait for Verification
- DNS propagation: up to 24 hours
- Once verified, your API is at: `https://api.predkt.app`

## Step 5: Connect Domain to Frontend

### If using Railway:
1. Follow same steps as backend
2. Use: `predkt.app` or `www.predkt.app`

### If using Vercel:
1. Go to project settings
2. Domain → Add custom domain
3. Enter: `predkt.app`
4. Follow Vercel's DNS instructions

## Step 6: Update Environment Variables

Once domains are verified, update all `.env` files:

### `server/.env` (Railway)
```
NEXT_PUBLIC_SUPABASE_URL=https://iffpxhemvquxgstcmnff.supabase.co
SUPABASE_SERVICE_KEY=sb_secret_LQtMyKItLBaI9nhWMPxg8g_doGc9FJU
API_FOOTBALL_KEY=2baabc52a043795f48d8b84ba9f5197a
RESEND_API_KEY=re_xxxxxxxxxxxxxxxxxx
NEXT_PUBLIC_APP_URL=https://predkt.app
PORT=3001
```

### `files/.env.local` (Vercel or Railway)
```
NEXT_PUBLIC_API_BASE_URL=https://api.predkt.app
NEXT_PUBLIC_APP_URL=https://predkt.app
```

## Step 7: Test Email Verification

1. Go to `https://predkt.app`
2. Sign up with a real email
3. Check inbox for verification email from `noreply@predkt.app`
4. Click verification link
5. Verify it works!

## Troubleshooting

### Domain not working
- Check DNS propagation: https://dnschecker.org
- DNS changes can take up to 24 hours
- Check Railway/Vercel domain settings

### Emails not sending
- Verify Resend domain: https://resend.com/domains
- Check RESEND_API_KEY is correct in Railway variables
- Check server logs in Railway dashboard

### Backend not accessible
- Verify public URL in Railway
- Check environment variables are set
- Look at deployment logs for errors

### Email from wrong address
- Make sure Resend domain is verified
- Check `from: "noreply@predkt.app"` in code
- Wait for DNS to fully propagate

## Next Steps

1. ✅ Configure Resend domain (predkt.app)
2. ✅ Deploy backend to Railway
3. ✅ Deploy frontend to Railway/Vercel
4. ✅ Configure custom domains
5. ✅ Test email verification
6. Monitor server logs for issues

## Monitoring & Logs

### Railway Logs
1. Go to your service
2. Click "Logs" tab
3. Watch for:
   - `[EMAIL SENT]` - successful email sends
   - `[EMAIL ERROR]` - email failures
   - Any errors during deployment

### Monitor Email Sending
1. Go to https://resend.com/dashboard
2. Check email activity
3. See delivery status and failures

