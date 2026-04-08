require("dotenv").config();
const express = require("express");
const cors    = require("cors");
const crypto  = require("crypto");
const { Resend } = require("resend");
const { createClient } = require("@supabase/supabase-js");

const app = express();
app.use(cors());
app.use(express.json());

const supabaseAdmin    = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

const supabaseStandard = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_ANON_KEY
);

const resend = process.env.RESEND_API_KEY
  ? new Resend(process.env.RESEND_API_KEY)
  : null;

const API_FOOTBALL_BASE = "https://v3.football.api-sports.io";

// ─── Scoring helpers (mirrored from lib/scoring.js) ───────────────
// WIN  = round(4 × odds × (conf/100) × dailyBonus × streakMult)
// LOSS = round(4 × odds × (conf/100) × 0.5)
const BASE = 4;

function getStreakMultiplier(winStreak) {
  const s = Math.max(0, parseInt(winStreak) || 0);
  return Math.min(1.0 + s * 0.1, 2.0);
}

function getDailyBonus(dailyStreak) {
  return (parseInt(dailyStreak) || 0) >= 2 ? 1.2 : 1.0;
}

function calcPointsWin(odds, confidence, winStreak, dailyStreak) {
  const o  = parseFloat(odds) || 1.0;
  const c  = Math.min(Math.max(parseInt(confidence) || 50, 0), 100) / 100;
  const sm = getStreakMultiplier(winStreak);
  const db = getDailyBonus(dailyStreak);
  return Math.max(1, Math.round(BASE * o * c * db * sm));
}

function calcPointsLoss(odds, confidence) {
  const o = parseFloat(odds) || 1.0;
  const c = Math.min(Math.max(parseInt(confidence) || 50, 0), 100) / 100;
  return Math.max(1, Math.round(BASE * o * c * 0.5));
}

function updateDailyStreak(profile) {
  const today     = new Date().toISOString().split("T")[0];
  const lastPick  = profile.last_pick_date;
  if (lastPick === today) {
    return { daily_streak: profile.daily_streak || 0, best_daily_streak: profile.best_daily_streak || 0, last_pick_date: today, dailyStreakChanged: false };
  }
  const yesterday = new Date(); yesterday.setDate(yesterday.getDate() - 1);
  const yStr      = yesterday.toISOString().split("T")[0];
  const newDaily  = lastPick === yStr ? (profile.daily_streak || 0) + 1 : 1;
  return {
    daily_streak:      newDaily,
    best_daily_streak: Math.max(profile.best_daily_streak || 0, newDaily),
    last_pick_date:    today,
    dailyStreakChanged: true,
  };
}

// ─── Middleware: requireAdmin ─────────────────────────────────────
async function requireAdmin(req, res, next) {
  const auth = req.headers.authorization;
  if (!auth?.startsWith("Bearer ")) return res.status(401).json({ error: "Unauthorized" });

  const token = auth.split(" ")[1];
  const { data: { user }, error } = await supabaseStandard.auth.getUser(token);
  if (error || !user) return res.status(401).json({ error: "Invalid token" });

  if (user.id !== process.env.ADMIN_USER_ID) return res.status(403).json({ error: "Forbidden" });

  next();
}

// ─── GET /api/live ────────────────────────────────────────────────
const LIVE_STATUSES   = ["1H","HT","2H","ET","BT","P","LIVE","INT"];
const FINISH_STATUSES = ["FT","AET","PEN","WO","AWD","ABD"];

app.get("/api/live", async (req, res) => {
  console.log("--- New Request to /api/live ---");
  try {
    const apiKey = process.env.API_FOOTBALL_KEY;
    if (!apiKey) {
      console.error("❌ SERVER ERROR: API_FOOTBALL_KEY is not defined in .env");
      return res.status(500).json({ error: "Server API Key missing" });
    }

    // Try both header styles if you're unsure which one your plan uses
    const headers = {
      "x-apisports-key": apiKey,
      "x-rapidapi-key": apiKey,
      "x-rapidapi-host": "v3.football.api-sports.io"
    };

    const response = await fetch(`${API_FOOTBALL_BASE}/fixtures?live=all`, { headers });

    console.log(`Football API Status: ${response.status}`);

    if (!response.ok) {
      const errText = await response.text();
      console.error("Football API Error:", errText);
      return res.status(response.status).json({ liveMatches: [], error: "API provider error" });
    }

    const data = await response.json();
    const fixtures = data.response || [];

    // Map the data
    const liveMatches = fixtures.map(f => ({
      fixtureId:   f.fixture.id,
      home:        f.teams.home.name,
      away:        f.teams.away.name,
      status:      f.fixture.status.short,
      elapsed:     f.fixture.status.elapsed,
      homeGoals:   f.goals.home ?? 0,
      awayGoals:   f.goals.away ?? 0,
      competition: f.league.name,
      isLive:      LIVE_STATUSES.includes(f.fixture.status.short),
      isFinished:  FINISH_STATUSES.includes(f.fixture.status.short),
    }));

    console.log(`Successfully found ${liveMatches.length} matches.`);

    // Explicitly send JSON
    res.setHeader('Content-Type', 'application/json');
    res.status(200).json({ liveMatches: liveMatches });

  } catch (err) {
    console.error("Server Crash:", err.message);
    res.status(500).json({ liveMatches: [], error: err.message });
  }
});

// ─── POST /api/resolve ────────────────────────────────────────────
app.post("/api/resolve", requireAdmin, async (req, res) => {
  const { pickId, result } = req.body;
  if (!pickId || !["correct", "wrong"].includes(result)) {
    return res.status(400).json({ error: "Invalid request" });
  }

  const { data: pick, error: pickError } = await supabaseAdmin.from("picks").select("*").eq("id", pickId).single();
  if (pickError || !pick) return res.status(404).json({ error: "Pick not found" });
  if (pick.result !== "pending") return res.status(400).json({ error: "Pick already resolved" });

  const { data: profile, error: profileError } = await supabaseAdmin
    .from("profiles")
    .select("current_streak, best_streak, weekly_points, total_points, daily_streak, best_daily_streak, last_pick_date")
    .eq("id", pick.user_id).single();
  if (profileError || !profile) return res.status(500).json({ error: "Could not find user profile" });

  const currentStreak = parseInt(profile.current_streak) || 0;
  const bestStreak    = parseInt(profile.best_streak)    || 0;

  let newStreak = 0, finalPoints = 0;
  if (result === "correct") {
    newStreak   = currentStreak + 1;
    finalPoints = calcPointsWin(pick.odds, pick.confidence, newStreak, profile.daily_streak);
  } else {
    finalPoints = -calcPointsLoss(pick.odds, pick.confidence);
  }
  const multiplier  = getStreakMultiplier(newStreak);
  const basePoints  = finalPoints > 0 ? finalPoints : Math.abs(finalPoints);

  const newBest         = Math.max(bestStreak, newStreak);
  const newWeeklyPoints = (parseInt(profile.weekly_points) || 0) + finalPoints;
  const newTotalPoints  = (parseInt(profile.total_points)  || 0) + finalPoints;
  const dailyUpdate     = updateDailyStreak(profile);

  await supabaseAdmin.from("picks").update({
    result,
    points_earned:            finalPoints,
    streak_multiplier:        multiplier,
    points_before_multiplier: result === "correct" ? basePoints : null,
  }).eq("id", pickId);

  await supabaseAdmin.from("profiles").update({
    current_streak:    newStreak,
    best_streak:       newBest,
    weekly_points:     newWeeklyPoints,
    total_points:      newTotalPoints,
    daily_streak:      dailyUpdate.daily_streak,
    best_daily_streak: dailyUpdate.best_daily_streak,
    last_pick_date:    dailyUpdate.last_pick_date,
  }).eq("id", pick.user_id);

  res.json({ pointsEarned: finalPoints, basePoints, multiplier, newStreak, newBest, dailyStreak: dailyUpdate.daily_streak, bestDailyStreak: dailyUpdate.best_daily_streak, dailyStreakChanged: dailyUpdate.dailyStreakChanged });
});

// ─── POST /api/settle ─────────────────────────────────────────────
app.post("/api/settle", requireAdmin, async (req, res) => {
  const { match, homeScore, awayScore } = req.body;
  if (!match || homeScore === undefined || awayScore === undefined) {
    return res.status(400).json({ error: "Missing match or scores" });
  }

  const { data: picks, error: fetchError } = await supabaseAdmin.from("picks").select("*").eq("match", match).eq("result", "pending");
  if (fetchError) return res.status(500).json({ error: fetchError.message });
  if (!picks || picks.length === 0) return res.json({ settled: 0, results: [] });

  const home = parseInt(homeScore), away = parseInt(awayScore), totalGoals = home + away;
  const results = [], profileCache = {};

  for (const pick of picks) {
    const market = pick.market.toLowerCase();
    let correct = false, skip = false;

    if      (market.includes("home win"))   correct = home > away;
    else if (market.includes("away win"))   correct = away > home;
    else if (market.includes("draw"))       correct = home === away;
    else if (market.includes("over 0.5"))  correct = totalGoals > 0.5;
    else if (market.includes("under 0.5")) correct = totalGoals < 0.5;
    else if (market.includes("over 1.5"))  correct = totalGoals > 1.5;
    else if (market.includes("under 1.5")) correct = totalGoals < 1.5;
    else if (market.includes("over 2.5"))  correct = totalGoals > 2.5;
    else if (market.includes("under 2.5")) correct = totalGoals < 2.5;
    else if (market.includes("over 3.5"))  correct = totalGoals > 3.5;
    else if (market.includes("under 3.5")) correct = totalGoals < 3.5;
    else if (market.includes("both score")) correct = home > 0 && away > 0;
    else if (market.includes("not both"))   correct = home === 0 || away === 0;
    else { skip = true; }

    if (skip) { results.push({ id: pick.id, market: pick.market, skipped: true }); continue; }

    const result = correct ? "correct" : "wrong";

    if (!profileCache[pick.user_id]) {
      const { data: p } = await supabaseAdmin.from("profiles")
        .select("current_streak, best_streak, weekly_points, total_points, daily_streak, best_daily_streak, last_pick_date")
        .eq("id", pick.user_id).single();
      profileCache[pick.user_id] = p;
    }

    const profile       = profileCache[pick.user_id];
    const currentStreak = parseInt(profile?.current_streak) || 0;

    let newStreak = 0, finalPoints = 0;
    if (result === "correct") {
      newStreak   = currentStreak + 1;
      finalPoints = calcPointsWin(pick.odds, pick.confidence, newStreak, profile?.daily_streak);
    } else {
      finalPoints = -calcPointsLoss(pick.odds, pick.confidence);
    }
    const multiplier = getStreakMultiplier(newStreak);
    const basePoints = Math.abs(finalPoints);

    const newBest  = Math.max(parseInt(profile?.best_streak) || 0, newStreak);
    const dailyUp  = updateDailyStreak(profile);

    profileCache[pick.user_id] = {
      ...profile,
      current_streak:    newStreak,
      best_streak:       newBest,
      weekly_points:     (parseInt(profile?.weekly_points) || 0) + finalPoints,
      total_points:      (parseInt(profile?.total_points)  || 0) + finalPoints,
      daily_streak:      dailyUp.daily_streak,
      best_daily_streak: dailyUp.best_daily_streak,
      last_pick_date:    dailyUp.last_pick_date,
    };

    await supabaseAdmin.from("picks").update({
      result,
      points_earned:            finalPoints,
      streak_multiplier:        multiplier,
      points_before_multiplier: result === "correct" ? basePoints : null,
    }).eq("id", pick.id);

    await supabaseAdmin.from("profiles").update(profileCache[pick.user_id]).eq("id", pick.user_id);

    results.push({ id: pick.id, market: pick.market, result, pointsEarned: finalPoints, multiplier, newStreak });
  }

  res.json({ settled: results.filter(r => !r.skipped).length, results });
});

// ─── POST /api/simulate ───────────────────────────────────────────
app.post("/api/simulate", async (req, res) => {
  const { picks, result, perPickResults } = req.body;
  if (!picks) return res.status(400).json({ error: "Missing picks" });

  const userIds = [...new Set(picks.map(p => p.user_id))];
  const { data: profiles } = await supabaseAdmin.from("profiles")
    .select("id, username, current_streak")
    .in("id", userIds);

  const streakMap     = {};
  (profiles || []).forEach(p => { streakMap[p.id] = p.current_streak || 0; });
  const runningStreak = { ...streakMap };

  const simulated = picks.map(p => {
    const pickResult = (perPickResults && perPickResults[p.id]) || result || "correct";
    const mult       = p.difficulty_multiplier || 1.0;
    const userId     = p.user_id;

    let finalPoints = 0, basePoints = 0, streakMult = 1.0;
    let newStreak   = runningStreak[userId] || 0;

    if (pickResult === "correct") {
      newStreak   = (runningStreak[userId] || 0) + 1;
      streakMult  = getStreakMultiplier(newStreak);
      basePoints  = calcPointsWin(p.odds, p.confidence, mult, p.difficulty);
      finalPoints = Math.round(basePoints * streakMult);
    } else {
      newStreak   = 0;
      basePoints  = calcPointsLoss(p.confidence, mult, p.difficulty);
      finalPoints = -basePoints;
    }

    runningStreak[userId] = newStreak;

    return {
      id:           p.id,
      username:     p.profiles?.username ?? "Unknown",
      market:       p.market,
      match:        p.match,
      confidence:   p.confidence,
      odds:         p.odds,
      difficulty:   p.difficulty,
      result:       pickResult,
      basePoints:   pickResult === "correct" ? basePoints : null,
      streakBefore: streakMap[userId] || 0,
      streakAfter:  newStreak,
      streakMult,
      points:       finalPoints,
    };
  });

  res.json({ simulated });
});

// ─── POST /api/invite-league ──────────────────────────────────────
app.post("/api/invite-league", async (req, res) => {
  const { leagueId, inviterUserId, email } = req.body;
  if (!leagueId || !inviterUserId || !email) return res.status(400).json({ error: "Missing fields" });

  const { data: authData, error: authError } = await supabaseAdmin.auth.admin.listUsers();
  if (authError) return res.status(500).json({ error: "Could not search users" });

  const targetUser = authData.users.find(u => u.email?.toLowerCase() === email.toLowerCase());
  if (!targetUser) return res.status(404).json({ error: "No Predkt account found with that email" });

  const { data: profile } = await supabaseAdmin.from("profiles").select("is_anonymous, username").eq("id", targetUser.id).single();
  if (profile?.is_anonymous) return res.status(400).json({ error: "That user hasn't created a full account yet" });

  const { data: existing } = await supabaseAdmin.from("league_members").select("id").eq("league_id", leagueId).eq("user_id", targetUser.id).single();
  if (existing) return res.status(400).json({ error: "That user is already in this league" });

  const { error: joinError } = await supabaseAdmin.from("league_members").insert({ league_id: leagueId, user_id: targetUser.id });
  if (joinError) return res.status(500).json({ error: joinError.message });

  res.json({ username: profile?.username || email });
});

// ─── POST /api/confirm-email ──────────────────────────────────────
// Confirms the email for an existing unconfirmed account so they can log in
app.post("/api/confirm-email", async (req, res) => {
  const { email } = req.body;
  if (!email) return res.status(400).json({ error: "Missing email" });

  const { data, error } = await supabaseAdmin.auth.admin.listUsers();
  if (error) return res.status(500).json({ error: "Could not look up user" });

  const user = (data?.users || []).find(u => u.email?.toLowerCase() === email.toLowerCase());
  if (!user) return res.status(404).json({ error: "No account found with that email" });
  if (user.email_confirmed_at) return res.json({ ok: true }); // already confirmed

  const { error: updateError } = await supabaseAdmin.auth.admin.updateUserById(user.id, { email_confirm: true });
  if (updateError) return res.status(500).json({ error: updateError.message });

  res.json({ ok: true });
});

// ─── POST /api/signup ─────────────────────────────────────────────
// Creates a new account with email pre-confirmed (no confirmation email sent)
app.post("/api/signup", async (req, res) => {
  const { email, password, username } = req.body;
  if (!email || !password || !username) return res.status(400).json({ error: "Missing fields" });

  // Check if email already registered
  const { data: existing } = await supabaseAdmin.auth.admin.listUsers();
  const alreadyExists = (existing?.users || []).find(u => u.email?.toLowerCase() === email.toLowerCase());
  if (alreadyExists) return res.status(400).json({ error: "An account with that email already exists" });

  // Create user WITHOUT pre-confirming email — will send verification email instead
  const { data, error } = await supabaseAdmin.auth.admin.createUser({
    email,
    password,
    email_confirm: false, // Changed: don't auto-confirm, send verification instead
  });
  if (error) return res.status(400).json({ error: error.message });

  const userId = data.user.id;

  // Create profile
  const { error: profileError } = await supabaseAdmin.from("profiles").upsert({
    id:           userId,
    username:     username.trim(),
    display_name: username.trim(),
    is_anonymous: false,
    email_verified: false,
  }, { onConflict: "id" });

  if (profileError) return res.status(500).json({ error: profileError.message });

  // Generate and send verification email
  const token = generateVerificationToken();
  const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();

  await supabase
    .from("profiles")
    .update({
      verification_token: token,
      token_expires_at: expiresAt
    })
    .eq("id", userId);

  // Send verification email
  const verificationUrl = `${process.env.NEXT_PUBLIC_APP_URL || "http://localhost:3000"}/verify?token=${token}&userId=${userId}`;
  await sendVerificationEmail(email, verificationUrl);

  res.json({ userId });
});

// ─── POST /api/upgrade ────────────────────────────────────────────
// Links email+password to an existing anonymous account, sends verification email
app.post("/api/upgrade", async (req, res) => {
  const { userId, email, password } = req.body;
  if (!userId || !email || !password) return res.status(400).json({ error: "Missing fields" });

  // Check email not already taken by another account
  const { data: existing } = await supabaseAdmin.auth.admin.listUsers();
  const taken = (existing?.users || []).find(u => u.email?.toLowerCase() === email.toLowerCase() && u.id !== userId);
  if (taken) return res.status(400).json({ error: "An account with that email already exists" });

  // Update the anonymous user's email+password WITHOUT pre-confirming
  const { error } = await supabaseAdmin.auth.admin.updateUserById(userId, {
    email,
    password,
    email_confirm: false, // Changed: don't auto-confirm, send verification instead
  });
  if (error) return res.status(400).json({ error: error.message });

  // Mark profile as no longer anonymous and set email_verified to false
  await supabaseAdmin.from("profiles").update({ is_anonymous: false, email_verified: false }).eq("id", userId);

  // Generate and send verification email
  const token = generateVerificationToken();
  const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();

  await supabase
    .from("profiles")
    .update({
      verification_token: token,
      token_expires_at: expiresAt
    })
    .eq("id", userId);

  // Send verification email
  const verificationUrl = `${process.env.NEXT_PUBLIC_APP_URL || "http://localhost:3000"}/verify?token=${token}&userId=${userId}`;
  await sendVerificationEmail(email, verificationUrl);

  res.json({ ok: true });
});

// ─── Helper: Generate email verification token ─────────────────────
function generateVerificationToken() {
  return crypto.randomBytes(32).toString("hex");
}

// ─── Helper: Send verification email via Resend ──────────────────────
async function sendVerificationEmail(email, verificationUrl) {
  if (resend) {
    try {
      await resend.emails.send({
        from: "noreply@predkt.app",
        to: email,
        subject: "Verify your email - Predkt",
        html: `
          <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; max-width: 600px; margin: 0 auto; color: #333;">
            <div style="background: linear-gradient(135deg, #6c63ff, #a855f7); padding: 20px; text-align: center; border-radius: 12px 12px 0 0;">
              <h1 style="color: white; margin: 0; font-size: 28px;">🎯 Predkt</h1>
            </div>

            <div style="padding: 30px; background: #f9f9f9; border-radius: 0 0 12px 12px;">
              <h2 style="color: #1a1a1f; margin-top: 0;">Verify your email</h2>

              <p style="color: #4a4958; line-height: 1.6; font-size: 14px;">
                Welcome to Predkt! To get started and access all features, please verify your email by clicking the button below.
              </p>

              <div style="margin: 30px 0; text-align: center;">
                <a href="${verificationUrl}" style="display: inline-block; padding: 14px 40px; background: linear-gradient(135deg, #6c63ff, #8a83ff); color: white; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 14px;">
                  Verify Email
                </a>
              </div>

              <p style="color: #8b8a99; font-size: 13px; margin: 20px 0;">
                Or copy this link:<br/>
                <span style="word-break: break-all; color: #6c63ff;">${verificationUrl}</span>
              </p>

              <hr style="border: none; border-top: 1px solid #e5e5e5; margin: 30px 0;">

              <p style="color: #8b8a99; font-size: 12px; margin: 0;">
                This link expires in 24 hours. If you didn't create this account, you can ignore this email.
              </p>
            </div>
          </div>
        `
      });
      console.log(`[EMAIL SENT] Verification email sent to ${email}`);
      return true;
    } catch (err) {
      console.error(`[EMAIL ERROR] Failed to send to ${email}:`, err.message);
      return false;
    }
  } else {
    // Development mode - log the link
    console.log(`[EMAIL] Verification link for ${email}:\n${verificationUrl}`);
    return true;
  }
}

// ─── POST /api/send-verification-email ────────────────────────────
// Sends a verification email to the user
app.post("/api/send-verification-email", async (req, res) => {
  const { userId, email } = req.body;
  if (!userId || !email) return res.status(400).json({ error: "Missing fields" });

  try {
    const token = generateVerificationToken();
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(); // 24 hours

    // Store token in profiles table
    const { error: updateError } = await supabase
      .from("profiles")
      .update({
        verification_token: token,
        token_expires_at: expiresAt
      })
      .eq("id", userId);

    if (updateError) {
      return res.status(500).json({ error: "Failed to generate verification token" });
    }

    // Send verification email via helper function
    const verificationUrl = `${process.env.NEXT_PUBLIC_APP_URL || "http://localhost:3000"}/verify?token=${token}&userId=${userId}`;
    await sendVerificationEmail(email, verificationUrl);

    res.json({ ok: true, message: "Verification email sent" });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─── POST /api/verify-email ──────────────────────────────────────
// Verifies the email token and marks user as verified
app.post("/api/verify-email", async (req, res) => {
  const { userId, token } = req.body;
  if (!userId || !token) return res.status(400).json({ error: "Missing fields" });

  try {
    // Get profile to check token
    const { data: profile, error: fetchError } = await supabase
      .from("profiles")
      .select("verification_token, token_expires_at")
      .eq("id", userId)
      .single();

    if (fetchError || !profile) {
      return res.status(404).json({ error: "User not found" });
    }

    // Check token validity
    if (profile.verification_token !== token) {
      return res.status(400).json({ error: "Invalid token" });
    }

    // Check token expiration
    if (new Date(profile.token_expires_at) < new Date()) {
      return res.status(400).json({ error: "Token expired" });
    }

    // Mark email as verified
    const { error: updateError } = await supabase
      .from("profiles")
      .update({
        email_verified: true,
        verification_token: null,
        token_expires_at: null
      })
      .eq("id", userId);

    if (updateError) {
      return res.status(500).json({ error: "Failed to verify email" });
    }

    res.json({ ok: true, message: "Email verified successfully" });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─── Start ────────────────────────────────────────────────────────
const PORT = process.env.PORT || 3001;
app.listen(PORT, () => console.log(`predkt server running on port ${PORT}`));
