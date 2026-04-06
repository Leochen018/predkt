# Email Verification Setup Guide

## Overview
The email verification feature sends verification emails to users after they create an account or upgrade from guest mode. Currently, the server logs verification links to the console for development. For production, you need to integrate with an email service.

## Development Setup

### Testing Locally
1. Verification links are logged to the server console
2. Look for messages like: `[EMAIL] Verification email for user@example.com:\nhttps://...`
3. Copy the verification URL and paste it into your browser
4. The app will automatically verify the email

## Production Setup - Option 1: Resend (Recommended)

Resend is a simple email API service perfect for transactional emails.

### Steps:
1. **Sign up for Resend**: https://resend.com
2. **Get your API key**: https://resend.com/api-keys
3. **Add to `.env` file** (server/.env):
   ```
   RESEND_API_KEY=your_api_key_here
   ```

4. **Install Resend package**:
   ```bash
   cd server
   npm install resend
   ```

5. **Update server/index.js** - Replace the email sending section in `/api/send-verification-email`:
   ```javascript
   // Add at top of file:
   const { Resend } = require("resend");
   const resend = new Resend(process.env.RESEND_API_KEY);

   // In the send-verification-email endpoint, replace the console.log section with:
   if (process.env.RESEND_API_KEY) {
     try {
       await resend.emails.send({
         from: "noreply@yourdomain.com", // Update with your domain
         to: email,
         subject: "Verify your email - Predkt",
         html: `
           <h2>Verify Your Email</h2>
           <p>Welcome to Predkt!</p>
           <p><a href="${verificationUrl}" style="padding: 10px 20px; background-color: #6c63ff; color: white; text-decoration: none; border-radius: 5px;">Verify Email</a></p>
           <p>Or copy this link: ${verificationUrl}</p>
           <p>This link expires in 24 hours.</p>
         `
       });
     } catch (err) {
       console.error("Failed to send email via Resend:", err);
       console.log(`[FALLBACK] Verification link: ${verificationUrl}`);
     }
   } else {
     console.log(`[EMAIL] Verification link for ${email}:\n${verificationUrl}`);
   }
   ```

## Production Setup - Option 2: Supabase Email Service

Supabase has a built-in email service but requires template setup in the dashboard.

### Steps:
1. Go to your Supabase project dashboard
2. Navigate to: Authentication > Email Templates
3. Create a custom template or use the existing one
4. The verification link should be: `{{ .ConfirmationURL }}`

## Production Setup - Option 3: SendGrid

### Steps:
1. **Sign up for SendGrid**: https://sendgrid.com
2. **Create an API key**: https://app.sendgrid.com/settings/api_keys
3. **Add to `.env` file** (server/.env):
   ```
   SENDGRID_API_KEY=your_api_key_here
   ```

4. **Install SendGrid package**:
   ```bash
   cd server
   npm install @sendgrid/mail
   ```

5. **Update server/index.js** - Replace email sending section:
   ```javascript
   // Add at top of file:
   const sgMail = require("@sendgrid/mail");
   sgMail.setApiKey(process.env.SENDGRID_API_KEY);

   // In the send-verification-email endpoint:
   if (process.env.SENDGRID_API_KEY) {
     try {
       await sgMail.send({
         to: email,
         from: "noreply@yourdomain.com", // Update with your domain
         subject: "Verify your email - Predkt",
         html: `
           <h2>Verify Your Email</h2>
           <p>Welcome to Predkt!</p>
           <p><a href="${verificationUrl}">Verify Email</a></p>
           <p>This link expires in 24 hours.</p>
         `
       });
     } catch (err) {
       console.error("Failed to send email via SendGrid:", err);
       console.log(`[FALLBACK] Verification link: ${verificationUrl}`);
     }
   }
   ```

## Environment Variables

### Server (.env)
```bash
# Required
NEXT_PUBLIC_SUPABASE_URL=your_supabase_url
SUPABASE_SERVICE_KEY=your_service_key
NEXT_PUBLIC_APP_URL=https://yourdomain.com  # For production

# Email service (choose one)
RESEND_API_KEY=optional_resend_key
SENDGRID_API_KEY=optional_sendgrid_key
```

### Frontend (.env.local)
```bash
NEXT_PUBLIC_API_BASE_URL=https://your-api.com  # Your backend URL
NEXT_PUBLIC_APP_URL=https://yourdomain.com     # For email verification links
```

## Testing Email Sending

1. **Development**: Check server console for verification links
2. **Production**: 
   - Create a test account with a valid email address
   - Check the inbox (including spam folder)
   - Click the verification link
   - Verify that access is granted to leaderboard and leagues

## Troubleshooting

### Emails not arriving
- Check spam/junk folder
- Verify email service credentials are correct
- Check server logs for errors: `[EMAIL] Verification email...`
- Try resending by signing up again

### Verification link not working
- Ensure `NEXT_PUBLIC_APP_URL` is set correctly
- Token expires after 24 hours (user can sign up again)
- Check browser console for errors

### Email service integration issues
- Verify API keys are correct in `.env`
- For Resend: ensure you own the domain or use Resend's default domain
- For SendGrid: check that the "from" email is verified in your account
- Check server logs for error messages

## Email Template Recommendations

### Subject Line
```
Verify your email - Predkt
```

### Email Content
```
Hi there!

Welcome to Predkt! To get started and access all features, please verify your email by clicking the button below:

[VERIFY EMAIL BUTTON]

Or copy this link: [VERIFICATION_URL]

This link expires in 24 hours.

Questions? Reply to this email.

Best,
The Predkt Team
```

## Next Steps

1. Choose an email service (Resend, SendGrid, or Supabase)
2. Add API credentials to `.env`
3. Update `server/index.js` with the service integration
4. Test email sending in development
5. Deploy and verify in production

