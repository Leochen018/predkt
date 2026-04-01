require("dotenv").config();
const express = require("express");
const cors    = require("cors");
const { createClient } = require("@supabase/supabase-js");

const app = express();
app.use(cors());
app.use(express.json());

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

const API_FOOTBALL_BASE    = "https://v3.football.api-sports.io";
const apiFootballHeaders = () => ({
  "x-rapidapi-key":  process.env.API_FOOTBALL_KEY,
  "x-rapidapi-host": "v3.football.api-sports.io",
});

// ─── Scoring helpers (mirrored from lib/scoring.js) ───────────────
const BASE      = 4;
const TIER_CAPS = { easy: 2.0, medium: 3.5, hard: 5.0, extreme: 8.0 };

function confWinScale(conf)  { const c = Math.min(Math.max(parseInt(conf)||50, 10), 90)/100; return 0.6 + c*0.4;  }
function confLossScale(conf) { const c = Math.min(Math.max(parseInt(conf)||50, 10), 90)/100; return 0.1 + c*0.25; }

function calcPointsWin(odds, confidence, diffMult, diffKey) {
  const d   = parseFloat(diffMult) || 1.0;
  const raw = Math.round(BASE * d * confWinScale(confidence));
  const cap = Math.round(BASE * d * (TIER_CAPS[diffKey] || 2.0));
  return Math.min(raw, cap);
}

function calcPointsLoss(confidence, diffMult, diffKey) {
  const d   = parseFloat(diffMult) || 1.0;
  const cap = diffKey === "extreme" ? 8 : 99;
  return Math.min(Math.round(BASE * d * confLossScale(confidence)), cap);
}

function getStreakMultiplier(streak) {
  const s = parseInt(streak) || 0;
  if (s >= 5) return 2.0;
  if (s >= 3) return 1.5;
  return 1.0;
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

// ─── GET /api/live ────────────────────────────────────────────────
const LIVE_STATUSES   = ["1H","HT","2H","ET","BT","P","LIVE","INT"];
const FINISH_STATUSES = ["FT","AET","PEN","WO","AWD","ABD"];

app.get("/api/live", async (req, res) => {
  try {
    const response = await fetch(`${API_FOOTBALL_BASE}/fixtures?live=all`, { headers: apiFootballHeaders() });
    if (!response.ok) return res.json({ liveMatches: [], error: "API unavailable" });

    const data     = await response.json();
    const fixtures = data.response || [];

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

    res.set("Cache-Control", "no-store").json({ liveMatches });
  } catch (err) {
    res.json({ liveMatches: [], error: err.message });
  }
});

// ─── POST /api/resolve ────────────────────────────────────────────
app.post("/api/resolve", async (req, res) => {
  const { pickId, result } = req.body;
  if (!pickId || !["correct", "wrong"].includes(result)) {
    return res.status(400).json({ error: "Invalid request" });
  }

  const { data: pick, error: pickError } = await supabase.from("picks").select("*").eq("id", pickId).single();
  if (pickError || !pick) return res.status(404).json({ error: "Pick not found" });
  if (pick.result !== "pending") return res.status(400).json({ error: "Pick already resolved" });

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("current_streak, best_streak, weekly_points, total_points, daily_streak, best_daily_streak, last_pick_date")
    .eq("id", pick.user_id).single();
  if (profileError || !profile) return res.status(500).json({ error: "Could not find user profile" });

  const currentStreak = parseInt(profile.current_streak) || 0;
  const bestStreak    = parseInt(profile.best_streak)    || 0;
  const diffMult      = parseFloat(pick.difficulty_multiplier) || 1.0;

  let newStreak   = 0, multiplier = 1.0, basePoints = 0, finalPoints = 0;
  if (result === "correct") {
    newStreak   = currentStreak + 1;
    multiplier  = getStreakMultiplier(newStreak);
    basePoints  = calcPointsWin(pick.odds, pick.confidence, diffMult, pick.difficulty);
    finalPoints = Math.round(basePoints * multiplier);
  } else {
    basePoints  = calcPointsLoss(pick.confidence, diffMult, pick.difficulty);
    finalPoints = -basePoints;
  }

  const newBest         = Math.max(bestStreak, newStreak);
  const newWeeklyPoints = (parseInt(profile.weekly_points) || 0) + finalPoints;
  const newTotalPoints  = (parseInt(profile.total_points)  || 0) + finalPoints;
  const dailyUpdate     = updateDailyStreak(profile);

  await supabase.from("picks").update({
    result,
    points_earned:            finalPoints,
    streak_multiplier:        multiplier,
    points_before_multiplier: result === "correct" ? basePoints : null,
  }).eq("id", pickId);

  await supabase.from("profiles").update({
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
app.post("/api/settle", async (req, res) => {
  const { match, homeScore, awayScore } = req.body;
  if (!match || homeScore === undefined || awayScore === undefined) {
    return res.status(400).json({ error: "Missing match or scores" });
  }

  const { data: picks, error: fetchError } = await supabase.from("picks").select("*").eq("match", match).eq("result", "pending");
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
      const { data: p } = await supabase.from("profiles")
        .select("current_streak, best_streak, weekly_points, total_points, daily_streak, best_daily_streak, last_pick_date")
        .eq("id", pick.user_id).single();
      profileCache[pick.user_id] = p;
    }

    const profile       = profileCache[pick.user_id];
    const currentStreak = parseInt(profile?.current_streak) || 0;
    const diffMult      = parseFloat(pick.difficulty_multiplier) || 1.0;

    let newStreak = 0, multiplier = 1.0, basePoints = 0, finalPoints = 0;
    if (result === "correct") {
      newStreak   = currentStreak + 1;
      multiplier  = getStreakMultiplier(newStreak);
      basePoints  = calcPointsWin(pick.odds, pick.confidence, diffMult, pick.difficulty);
      finalPoints = Math.round(basePoints * multiplier);
    } else {
      basePoints  = calcPointsLoss(pick.confidence, diffMult, pick.difficulty);
      finalPoints = -basePoints;
    }

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

    await supabase.from("picks").update({
      result,
      points_earned:            finalPoints,
      streak_multiplier:        multiplier,
      points_before_multiplier: result === "correct" ? basePoints : null,
    }).eq("id", pick.id);

    await supabase.from("profiles").update(profileCache[pick.user_id]).eq("id", pick.user_id);

    results.push({ id: pick.id, market: pick.market, result, pointsEarned: finalPoints, multiplier, newStreak });
  }

  res.json({ settled: results.filter(r => !r.skipped).length, results });
});

// ─── POST /api/simulate ───────────────────────────────────────────
app.post("/api/simulate", async (req, res) => {
  const { picks, result, perPickResults } = req.body;
  if (!picks) return res.status(400).json({ error: "Missing picks" });

  const userIds = [...new Set(picks.map(p => p.user_id))];
  const { data: profiles } = await supabase.from("profiles")
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

  const { data: authData, error: authError } = await supabase.auth.admin.listUsers();
  if (authError) return res.status(500).json({ error: "Could not search users" });

  const targetUser = authData.users.find(u => u.email?.toLowerCase() === email.toLowerCase());
  if (!targetUser) return res.status(404).json({ error: "No Predkt account found with that email" });

  const { data: profile } = await supabase.from("profiles").select("is_anonymous, username").eq("id", targetUser.id).single();
  if (profile?.is_anonymous) return res.status(400).json({ error: "That user hasn't created a full account yet" });

  const { data: existing } = await supabase.from("league_members").select("id").eq("league_id", leagueId).eq("user_id", targetUser.id).single();
  if (existing) return res.status(400).json({ error: "That user is already in this league" });

  const { error: joinError } = await supabase.from("league_members").insert({ league_id: leagueId, user_id: targetUser.id });
  if (joinError) return res.status(500).json({ error: joinError.message });

  res.json({ username: profile?.username || email });
});

// ─── POST /api/confirm-email ──────────────────────────────────────
// Confirms the email for an existing unconfirmed account so they can log in
app.post("/api/confirm-email", async (req, res) => {
  const { email } = req.body;
  if (!email) return res.status(400).json({ error: "Missing email" });

  const { data, error } = await supabase.auth.admin.listUsers();
  if (error) return res.status(500).json({ error: "Could not look up user" });

  const user = (data?.users || []).find(u => u.email?.toLowerCase() === email.toLowerCase());
  if (!user) return res.status(404).json({ error: "No account found with that email" });
  if (user.email_confirmed_at) return res.json({ ok: true }); // already confirmed

  const { error: updateError } = await supabase.auth.admin.updateUserById(user.id, { email_confirm: true });
  if (updateError) return res.status(500).json({ error: updateError.message });

  res.json({ ok: true });
});

// ─── POST /api/signup ─────────────────────────────────────────────
// Creates a new account with email pre-confirmed (no confirmation email sent)
app.post("/api/signup", async (req, res) => {
  const { email, password, username } = req.body;
  if (!email || !password || !username) return res.status(400).json({ error: "Missing fields" });

  // Check if email already registered
  const { data: existing } = await supabase.auth.admin.listUsers();
  const alreadyExists = (existing?.users || []).find(u => u.email?.toLowerCase() === email.toLowerCase());
  if (alreadyExists) return res.status(400).json({ error: "An account with that email already exists" });

  // Create user with email pre-confirmed — no confirmation email sent
  const { data, error } = await supabase.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (error) return res.status(400).json({ error: error.message });

  const userId = data.user.id;

  // Create profile
  const { error: profileError } = await supabase.from("profiles").upsert({
    id:           userId,
    username:     username.trim(),
    display_name: username.trim(),
    is_anonymous: false,
  }, { onConflict: "id" });

  if (profileError) return res.status(500).json({ error: profileError.message });

  res.json({ userId });
});

// ─── POST /api/upgrade ────────────────────────────────────────────
// Links email+password to an existing anonymous account (no confirmation email)
app.post("/api/upgrade", async (req, res) => {
  const { userId, email, password } = req.body;
  if (!userId || !email || !password) return res.status(400).json({ error: "Missing fields" });

  // Check email not already taken by another account
  const { data: existing } = await supabase.auth.admin.listUsers();
  const taken = (existing?.users || []).find(u => u.email?.toLowerCase() === email.toLowerCase() && u.id !== userId);
  if (taken) return res.status(400).json({ error: "An account with that email already exists" });

  // Update the anonymous user's email+password with email pre-confirmed
  const { error } = await supabase.auth.admin.updateUserById(userId, {
    email,
    password,
    email_confirm: true,
  });
  if (error) return res.status(400).json({ error: error.message });

  // Mark profile as no longer anonymous
  await supabase.from("profiles").update({ is_anonymous: false }).eq("id", userId);

  res.json({ ok: true });
});

// ─── Start ────────────────────────────────────────────────────────
const PORT = process.env.PORT || 3001;
app.listen(PORT, () => console.log(`predkt server running on port ${PORT}`));
