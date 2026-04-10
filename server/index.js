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
const SB_URL         = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
const SB_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;
const SB_ANON_KEY    = process.env.SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

if (!SB_URL) console.error("❌ MISSING: SUPABASE_URL");

const supabaseAdmin    = createClient(SB_URL, SB_SERVICE_KEY);
const supabaseStandard = createClient(SB_URL, SB_ANON_KEY);

const resend = process.env.RESEND_API_KEY
  ? new Resend(process.env.RESEND_API_KEY)
  : null;

const API_FOOTBALL_BASE = "https://v3.football.api-sports.io";

// --- 2. SCORING & STREAK LOGIC ---
// NEW FORMULA: Points = 10 + (100 - probability)
function calcPointsWin(probability) {
  const p = Math.min(99, Math.max(1, parseInt(probability) || 50));
  return Math.max(1, 10 + (100 - p));
}

function calcPointsLoss(probability) {
  return Math.max(1, Math.round(calcPointsWin(probability) / 2));
}

function getStreakMultiplier(winStreak) {
  const s = Math.max(0, parseInt(winStreak) || 0);
  return Math.min(1.0 + s * 0.1, 2.0);
}

function getDailyBonus(dailyStreak) {
  return (parseInt(dailyStreak) || 0) >= 2 ? 1.2 : 1.0;
}

function updateDailyStreak(profile) {
  const today    = new Date().toISOString().split("T")[0];
  const lastPick = profile.last_pick_date;
  if (lastPick === today) return { ...profile, dailyStreakChanged: false };
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

// --- 4. MATCH & ODDS HELPERS ---

const TOP_LEAGUE_IDS  = [39, 140, 135, 78, 61, 94, 88, 2, 3];
const LIVE_STATUSES   = ["1H", "HT", "2H", "ET", "BT", "P", "LIVE", "INT"];
const FINISH_STATUSES = ["FT", "AET", "PEN", "WO", "AWD", "ABD"];

async function fetchFixtures(params) {
  const apiKey  = process.env.API_FOOTBALL_KEY;
  const headers = { "x-apisports-key": apiKey };
  const query   = new URLSearchParams(params).toString();
  const response = await fetch(`${API_FOOTBALL_BASE}/fixtures?${query}`, { headers });
  const data = await response.json();
  return data.response || [];
}

async function fetchOddsForFixture(fixtureId) {
  try {
    const apiKey  = process.env.API_FOOTBALL_KEY;
    const headers = { "x-apisports-key": apiKey };
    const response = await fetch(
      `${API_FOOTBALL_BASE}/odds?fixture=${fixtureId}&bookmaker=8`,
      { headers }
    );
    const data      = await response.json();
    const bookmaker = data.response?.[0]?.bookmakers?.[0];
    if (!bookmaker) return null;

    const odds = {
      // Match Result
      homeWin: null, draw: null, awayWin: null,
      // Double Chance
      homeOrDraw: null, awayOrDraw: null, homeOrAway: null,
      // Draw No Bet
      dnbHome: null, dnbAway: null,
      // Goals
      over05: null, under05: null,
      over15: null, under15: null,
      over25: null, under25: null,
      over35: null, under35: null,
      over45: null, under45: null,
      // HT Goals
      htOver05: null, htUnder05: null,
      htOver15: null, htUnder15: null,
      // BTTS
      bttsYes: null, bttsNo: null,
      // HT Result
      htHomeWin: null, htDraw: null, htAwayWin: null,
      // Corners
      cornersOver75: null, cornersUnder75: null,
      cornersOver85: null, cornersUnder85: null,
      cornersOver95: null, cornersUnder95: null,
      cornersOver105: null, cornersUnder105: null,
      // Cards
      cardsOver15: null, cardsUnder15: null,
      cardsOver25: null, cardsUnder25: null,
      cardsOver35: null, cardsUnder35: null,
      // Clean Sheets
      homeCleanSheet: null, awayCleanSheet: null,
      // Player Props
      playerFirstGoal:  [],
      playerLastGoal:   [],
      playerAnytime:    [],
      playerToBeCarded: [],
      playerToAssist:   [],
    };

    const bets = bookmaker.bets || [];

    function val(betName, valueName) {
      const bet = bets.find(b => b.name === betName);
      return parseFloat(bet?.values?.find(v => v.value === valueName)?.odd) || null;
    }

    function playerList(betName) {
      const bet = bets.find(b => b.name === betName);
      if (!bet) return [];
      return bet.values
        .map(v => ({ name: v.value, odd: parseFloat(v.odd) || 0 }))
        .filter(v => v.odd > 0)
        .sort((a, b) => a.odd - b.odd)
        .slice(0, 10);
    }

    // Match Winner
    odds.homeWin = val("Match Winner", "Home");
    odds.draw    = val("Match Winner", "Draw");
    odds.awayWin = val("Match Winner", "Away");

    // Double Chance
    odds.homeOrDraw = val("Double Chance", "Home/Draw");
    odds.awayOrDraw = val("Double Chance", "Draw/Away");
    odds.homeOrAway = val("Double Chance", "Home/Away");

    // Draw No Bet
    odds.dnbHome = val("Draw No Bet", "Home");
    odds.dnbAway = val("Draw No Bet", "Away");

    // Goals Over/Under
    for (const line of ["0.5", "1.5", "2.5", "3.5", "4.5"]) {
      const key = line.replace(".", "");
      odds[`over${key}`]  = val("Goals Over/Under", `Over ${line}`);
      odds[`under${key}`] = val("Goals Over/Under", `Under ${line}`);
    }

    // First Half Goals
    odds.htOver05  = val("First Half Goals", "Over 0.5");
    odds.htUnder05 = val("First Half Goals", "Under 0.5");
    odds.htOver15  = val("First Half Goals", "Over 1.5");
    odds.htUnder15 = val("First Half Goals", "Under 1.5");

    // BTTS
    odds.bttsYes = val("Both Teams Score", "Yes");
    odds.bttsNo  = val("Both Teams Score", "No");

    // HT Result
    odds.htHomeWin = val("First Half Winner", "Home");
    odds.htDraw    = val("First Half Winner", "Draw");
    odds.htAwayWin = val("First Half Winner", "Away");

    // Corners
    for (const line of ["7.5", "8.5", "9.5", "10.5"]) {
      const key = line.replace(".", "");
      odds[`cornersOver${key}`]  = val("Total Corners", `Over ${line}`);
      odds[`cornersUnder${key}`] = val("Total Corners", `Under ${line}`);
    }

    // Cards
    for (const line of ["1.5", "2.5", "3.5"]) {
      const key = line.replace(".", "");
      odds[`cardsOver${key}`]  = val("Total Bookings", `Over ${line}`);
      odds[`cardsUnder${key}`] = val("Total Bookings", `Under ${line}`);
    }

    // Clean Sheets
    odds.homeCleanSheet = val("Clean Sheet", "Home");
    odds.awayCleanSheet = val("Clean Sheet", "Away");

    // Player Props
    odds.playerFirstGoal  = playerList("First Goalscorer");
    odds.playerLastGoal   = playerList("Last Goalscorer");
    odds.playerAnytime    = playerList("Anytime Goalscorer");
    odds.playerToBeCarded = playerList("Player To Be Carded");
    odds.playerToAssist   = playerList("Player To Assist");

    return odds;
  } catch (err) {
    console.warn(`⚠️ Odds fetch failed for fixture ${fixtureId}: ${err.message}`);
    return null;
  }
}

// Fetch odds in batches to avoid rate limits
async function fetchOddsInBatches(fixtures, batchSize = 10) {
  const results = [];
  for (let i = 0; i < fixtures.length; i += batchSize) {
    const batch        = fixtures.slice(i, i + batchSize);
    const batchResults = await Promise.all(
      batch.map(f => fetchOddsForFixture(f.fixture.id))
    );
    results.push(...batchResults);
    if (i + batchSize < fixtures.length) {
      await new Promise(r => setTimeout(r, 200)); // 200ms between batches
    }
  }
  return results;
}

function mapFixture(f, odds = null) {
  return {
    fixtureId:   f.fixture.id,
    home:        f.teams.home.name,
    away:        f.teams.away.name,
    status:      f.fixture.status.short,
    elapsed:     f.fixture.status.elapsed ?? null,
    homeGoals:   f.goals.home ?? 0,
    awayGoals:   f.goals.away ?? 0,
    competition: f.league.name,
    league_id:   f.league.id,
    date:        f.fixture.date,
    homeLogo:    f.teams.home.logo,
    awayLogo:    f.teams.away.logo,
    isLive:      LIVE_STATUSES.includes(f.fixture.status.short),
    isFinished:  FINISH_STATUSES.includes(f.fixture.status.short),
    odds:        odds, // null if unavailable — Swift falls back gracefully
  };
}

// --- 5. API ROUTES ---

app.get("/", (req, res) => res.send("Predkt API is Live"));

// GET /api/live — currently live matches only (no odds needed for live)
app.get("/api/live", async (req, res) => {
  try {
    const fixtures    = await fetchFixtures({ live: "all" });
    const liveMatches = fixtures.map(f => mapFixture(f, null));
    res.json({ liveMatches });
  } catch (err) {
    console.error("❌ /api/live error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/matches — upcoming matches with real odds for next 7 days
app.get("/api/matches", async (req, res) => {
  try {
    const today  = new Date().toISOString().split("T")[0];
    const next7  = new Date(Date.now() + 7 * 86400000).toISOString().split("T")[0];
    const now    = new Date();
    const season = now.getMonth() < 7 ? now.getFullYear() - 1 : now.getFullYear();

    console.log(`🔍 Fetching matches: season=${season}, from=${today}, to=${next7}`);

    const leagueRequests = TOP_LEAGUE_IDS.map(leagueId =>
      fetchFixtures({ league: leagueId, season, from: today, to: next7 })
    );
    const results     = await Promise.all(leagueRequests);
    const allFixtures = results.flat();

    console.log(`✅ Total fixtures found: ${allFixtures.length}`);

    // Deduplicate
    const seen   = new Set();
    const unique = allFixtures.filter(f => {
      if (seen.has(f.fixture.id)) return false;
      seen.add(f.fixture.id);
      return true;
    });

    // Fetch real odds for all fixtures in batches
    console.log(`🎰 Fetching odds for ${unique.length} fixtures...`);
    const oddsResults = await fetchOddsInBatches(unique);
    console.log(`✅ Odds fetched (${oddsResults.filter(Boolean).length}/${unique.length} had data)`);

    const liveMatches = unique
      .map((f, i) => mapFixture(f, oddsResults[i]))
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

  const { data: pick, error: pickErr } = await supabaseAdmin
    .from("picks").select("*").eq("id", pickId).single();
  if (pickErr) return res.status(404).json({ error: "Pick not found" });

  const { data: profile, error: profErr } = await supabaseAdmin
    .from("profiles").select("*").eq("id", pick.user_id).single();
  if (profErr) return res.status(404).json({ error: "Profile not found" });

  // Use stored probability, fall back to deriving from odds
  const probability = pick.probability
    || Math.min(99, Math.max(1, Math.round(100.0 / (pick.odds || 2.0))));

  let newStreak = 0, finalPoints = 0;

  if (result === "correct") {
    newStreak   = (profile.current_streak || 0) + 1;
    const streakBonus = getStreakMultiplier(newStreak);
    const dailyBonus  = getDailyBonus(profile.daily_streak);
    finalPoints = Math.round(calcPointsWin(probability) * streakBonus * dailyBonus);
  } else {
    finalPoints = -calcPointsLoss(probability);
  }

  const dailyUpdate = updateDailyStreak(profile);

  await supabaseAdmin.from("picks")
    .update({ result, points_earned: finalPoints })
    .eq("id", pickId);

  await supabaseAdmin.from("profiles")
    .update({
      current_streak:    result === "correct" ? newStreak : 0,
      best_streak:       Math.max(profile.best_streak || 0, newStreak),
      total_points:      (profile.total_points  || 0) + finalPoints,
      weekly_points:     (profile.weekly_points || 0) + finalPoints,
      daily_streak:      dailyUpdate.daily_streak,
      best_daily_streak: dailyUpdate.best_daily_streak,
      last_pick_date:    dailyUpdate.last_pick_date,
    })
    .eq("id", pick.user_id);

  res.json({ ok: true, points_earned: finalPoints });
});

// --- 6. EMAIL HELPERS ---
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