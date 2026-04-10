require("dotenv").config();
const express = require("express");
const cors    = require("cors");
const crypto  = require("crypto");
const { Resend } = require("resend");
const { createClient } = require("@supabase/supabase-js");

const app = express();
app.use(cors());
app.use(express.json());

// --- 1. CONNECTION BLOCK ---
const SB_URL = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
const SB_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;
const SB_ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

if (!SB_URL) console.error("❌ MISSING: SUPABASE_URL");

const supabaseAdmin = createClient(SB_URL, SB_SERVICE_KEY);
const supabaseStandard = createClient(SB_URL, SB_ANON_KEY);

const resend = process.env.RESEND_API_KEY
  ? new Resend(process.env.RESEND_API_KEY)
  : null;

const API_FOOTBALL_BASE = "https://v3.football.api-sports.io";

// --- 2. SCORING & STREAK LOGIC ---
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
  const today    = new Date().toISOString().split("T")[0];
  const lastPick = profile.last_pick_date;
  if (lastPick === today) {
    return { ...profile, dailyStreakChanged: false };
  }
  const yesterday = new Date();
  yesterday.setDate(yesterday.getDate() - 1);
  const yStr     = yesterday.toISOString().split("T")[0];
  const newDaily = lastPick === yStr ? (profile.daily_streak || 0) + 1 : 1;
  return {
    daily_streak:      newDaily,
    best_daily_streak: Math.max(profile.best_daily_streak || 0, newDaily),
    last_pick_date:    today,
    dailyStreakChanged: true,
  };
}

// --- 3. MIDDLEWARE ---
async function requireAdmin(req, res, next) {
  const auth = req.headers.authorization;
  if (!auth?.startsWith("Bearer ")) return res.status(401).json({ error: "Unauthorized" });
  const token = auth.split(" ")[1];
  const { data: { user }, error } = await supabaseStandard.auth.getUser(token);
  if (error || !user) return res.status(401).json({ error: "Invalid token" });
  if (user.id !== process.env.ADMIN_USER_ID) return res.status(403).json({ error: "Forbidden" });
  next();
}

// --- 4. MATCH HELPERS ---

const TOP_LEAGUE_IDS = [39, 140, 135, 78, 61, 94, 88, 2, 3];
const LIVE_STATUSES   = ["1H", "HT", "2H", "ET", "BT", "P", "LIVE", "INT"];
const FINISH_STATUSES = ["FT", "AET", "PEN", "WO", "AWD", "ABD"];

// Fetches fixtures from API-Football with given query params
async function fetchFixtures(params) {
  const apiKey = process.env.API_FOOTBALL_KEY;
  const headers = { "x-apisports-key": apiKey };
  const query = new URLSearchParams(params).toString();
  const response = await fetch(`${API_FOOTBALL_BASE}/fixtures?${query}`, { headers });
  const data = await response.json();
  return data.response || [];
}

// Maps a raw API-Football fixture to the shape Swift expects
function mapFixture(f) {
  return {
    fixtureId:   f.fixture.id,
    home:        f.teams.home.name,
    away:        f.teams.away.name,
    status:      f.fixture.status.short,
    elapsed:     f.fixture.status.elapsed ?? null,
    homeGoals:   f.goals.home ?? 0,
    awayGoals:   f.goals.away ?? 0,
    competition: f.league.name,
    league_id:   f.league.id,      // ✅ FIX: Swift uses this to filter top leagues
    date:        f.fixture.date,   // ✅ FIX: Swift uses this for date picker filtering
    isLive:      LIVE_STATUSES.includes(f.fixture.status.short),
    isFinished:  FINISH_STATUSES.includes(f.fixture.status.short),
  };
}

// --- 5. API ROUTES ---

app.get("/", (req, res) => res.send("Predkt API is Live"));

// GET /api/live — currently live matches only
app.get("/api/live", async (req, res) => {
  try {
    const fixtures = await fetchFixtures({ live: "all" });
    const liveMatches = fixtures.map(mapFixture);
    res.json({ liveMatches });
  } catch (err) {
    console.error("❌ /api/live error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/matches — upcoming matches for the next 7 days across all top leagues
app.get("/api/matches", async (req, res) => {
  try {
    const today = new Date().toISOString().split("T")[0];
    const next7 = new Date(Date.now() + 7 * 86400000).toISOString().split("T")[0];
    const now = new Date();
    const season = now.getMonth() < 7 ? now.getFullYear() - 1 : now.getFullYear();


    console.log(`🔍 Fetching matches: season=${season}, from=${today}, to=${next7}`);

    // Fetch all top leagues in parallel
    const leagueRequests = TOP_LEAGUE_IDS.map(leagueId =>
      fetchFixtures({ league: leagueId, season, from: today, to: next7 })
    );

    const results = await Promise.all(leagueRequests);
    const allFixtures = results.flat();


    console.log(`✅ Total fixtures found: ${allFixtures.length}`); // 👈 check Railway logs

    // Deduplicate by fixtureId
    const seen = new Set();
    const liveMatches = allFixtures
      .filter(f => {
        if (seen.has(f.fixture.id)) return false;
        seen.add(f.fixture.id);
        return true;
      })
      .map(mapFixture)
      .sort((a, b) => new Date(a.date) - new Date(b.date));

    res.json({ liveMatches });
  } catch (err) {
    console.error("❌ /api/matches error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

// POST /api/resolve — admin only, resolves a pick and updates points/streaks
app.post("/api/resolve", requireAdmin, async (req, res) => {
  const { pickId, result } = req.body;
  const { data: pick }    = await supabaseAdmin.from("picks").select("*").eq("id", pickId).single();
  const { data: profile } = await supabaseAdmin.from("profiles").select("*").eq("id", pick.user_id).single();

  let newStreak = 0, finalPoints = 0;
  if (result === "correct") {
    newStreak   = (profile.current_streak || 0) + 1;
    finalPoints = calcPointsWin(pick.odds, pick.confidence, newStreak, profile.daily_streak);
  } else {
    finalPoints = -calcPointsLoss(pick.odds, pick.confidence);
  }

  const dailyUpdate = updateDailyStreak(profile);
  await supabaseAdmin.from("picks").update({ result, points_earned: finalPoints }).eq("id", pickId);
  await supabaseAdmin.from("profiles").update({
    current_streak: newStreak,
    daily_streak:   dailyUpdate.daily_streak,
  }).eq("id", pick.user_id);

  res.json({ ok: true });
});

// --- 6. EMAIL HELPERS (unused routes, kept for future use) ---
function generateVerificationToken() { return crypto.randomBytes(32).toString("hex"); }

async function sendVerificationEmail(email, verificationUrl) {
  if (resend) {
    await resend.emails.send({
      from:    "noreply@predkt.app",
      to:      email,
      subject: "Verify your email - Predkt",
      html:    `<p>Verify here: ${verificationUrl}</p>`,
    });
  }
}

// --- 7. START SERVER ---
const PORT = process.env.PORT || 8080;
app.listen(PORT, "0.0.0.0", () => {
  console.log(`✅ SERVER ACTIVE: Listening on port ${PORT}`);
});