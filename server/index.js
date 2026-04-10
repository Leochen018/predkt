require("dotenv").config();
const express = require("express");
const cors    = require("cors");
const crypto  = require("crypto");
const cron    = require("node-cron");
const { Resend } = require("resend");
const { createClient } = require("@supabase/supabase-js");

const app = express();
app.use(cors());
app.use(express.json());

const SB_URL         = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
const SB_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;
const SB_ANON_KEY    = process.env.SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
if (!SB_URL) console.error("❌ MISSING: SUPABASE_URL");
const supabaseAdmin    = createClient(SB_URL, SB_SERVICE_KEY);
const supabaseStandard = createClient(SB_URL, SB_ANON_KEY);
const resend = process.env.RESEND_API_KEY ? new Resend(process.env.RESEND_API_KEY) : null;
const API_FOOTBALL_BASE = "https://v3.football.api-sports.io";

// ============================================================
// IN-MEMORY CACHE
// ============================================================
const matchCache = {
  data: null, builtAt: null, ttl: 30 * 60 * 1000,
  isStale() { return !this.data || !this.builtAt || Date.now() - this.builtAt > this.ttl; },
  set(data) { this.data = data; this.builtAt = Date.now(); },
  invalidate() { this.data = null; this.builtAt = null; }
};
const oddsCache = new Map();
const ODDS_TTL  = 6 * 60 * 60 * 1000;
function getCachedOdds(id) {
  const e = oddsCache.get(id);
  if (!e) return null;
  if (Date.now() - e.cachedAt > ODDS_TTL) { oddsCache.delete(id); return null; }
  return e.odds;
}
function setCachedOdds(id, odds) { oddsCache.set(id, { odds, cachedAt: Date.now() }); }

// SCORING
function calcPointsWin(p) { return Math.max(1, 10 + (100 - Math.min(99, Math.max(1, parseInt(p)||50)))); }
function calcPointsLoss(p) { return Math.max(1, Math.round(calcPointsWin(p)/2)); }
function getStreakMultiplier(s) { return Math.min(1.0+(Math.max(0,parseInt(s)||0))*0.1,2.0); }
function getDailyBonus(d) { return (parseInt(d)||0)>=2?1.2:1.0; }
function updateDailyStreak(profile) {
  const today=new Date().toISOString().split("T")[0];
  if(profile.last_pick_date===today) return{...profile,dailyStreakChanged:false};
  const yesterday=new Date();yesterday.setDate(yesterday.getDate()-1);
  const yStr=yesterday.toISOString().split("T")[0];
  const newDaily=profile.last_pick_date===yStr?(profile.daily_streak||0)+1:1;
  return{daily_streak:newDaily,best_daily_streak:Math.max(profile.best_daily_streak||0,newDaily),last_pick_date:today,dailyStreakChanged:true};
}

async function requireAdmin(req,res,next){
  const auth=req.headers.authorization;
  if(!auth?.startsWith("Bearer ")) return res.status(401).json({error:"Unauthorized"});
  const{data:{user},error}=await supabaseStandard.auth.getUser(auth.split(" ")[1]);
  if(error||!user||user.id!==process.env.ADMIN_USER_ID) return res.status(403).json({error:"Forbidden"});
  next();
}

const TOP_LEAGUE_IDS  = [39,40,45,48,140,143,135,137,78,529,61,94,88,2,3,848,4,32];
const LIVE_STATUSES   = ["1H","HT","2H","ET","BT","P","LIVE","INT"];
const FINISH_STATUSES = ["FT","AET","PEN","WO","AWD","ABD"];

async function fetchFixtures(params) {
  const headers={"x-apisports-key":process.env.API_FOOTBALL_KEY};
  const res=await fetch(`${API_FOOTBALL_BASE}/fixtures?${new URLSearchParams(params)}`,{headers});
  return (await res.json()).response||[];
}

// ============================================================
// PARSE BETS — uses bet IDs (1-62) for reliable lookup
// ID list: 1-35, 37, 45, 62
// ============================================================
function parseBets(bets) {
  // ✅ Lookup by bet ID (reliable) with name fallback
  const byId   = (id)    => bets.find(b => b.id === id);
  const byName = (name)  => bets.find(b => b.name === name);
  const bet    = (id, fallbackName) => byId(id) || (fallbackName ? byName(fallbackName) : null);

  // Get a value from a specific bet
  const val = (id, valueName, fallbackName) => {
    const b = bet(id, fallbackName);
    return parseFloat(b?.values?.find(v => v.value === valueName)?.odd) || null;
  };

  // Get all values from a bet as array
  const allValues = (id, fallbackName) => {
    const b = bet(id, fallbackName);
    if (!b) return [];
    return b.values
      .map(v => ({ label: v.value, odd: parseFloat(v.odd) || 0 }))
      .filter(v => v.odd > 0);
  };

  // Player list helper
  const playerList = (id, fallbackName, limit = 12) => {
    const b = bet(id, fallbackName);
    if (!b) return [];
    return b.values
      .map(v => ({ name: v.value, odd: parseFloat(v.odd) || 0 }))
      .filter(v => v.odd > 0)
      .sort((a, b) => a.odd - b.odd)
      .slice(0, limit);
  };

  const odds = {
    // ID 1 — Match Winner (1X2)
    homeWin: val(1, "Home", "Match Winner"),
    draw:    val(1, "Draw", "Match Winner"),
    awayWin: val(1, "Away", "Match Winner"),

    // ID 2 — Home/Away (no draw)
    homeWinNoDraw: val(2, "Home", "Home/Away"),
    awayWinNoDraw: val(2, "Away", "Home/Away"),

    // ID 3 — Both Teams Score
    bttsYes: val(3, "Yes", "Both Teams Score"),
    bttsNo:  val(3, "No",  "Both Teams Score"),

    // ID 4 — Goals Over/Under (all lines)
    over05: val(4, "Over 0.5",  "Goals Over/Under"),
    under05:val(4, "Under 0.5", "Goals Over/Under"),
    over15: val(4, "Over 1.5",  "Goals Over/Under"),
    under15:val(4, "Under 1.5", "Goals Over/Under"),
    over25: val(4, "Over 2.5",  "Goals Over/Under"),
    under25:val(4, "Under 2.5", "Goals Over/Under"),
    over35: val(4, "Over 3.5",  "Goals Over/Under"),
    under35:val(4, "Under 3.5", "Goals Over/Under"),
    over45: val(4, "Over 4.5",  "Goals Over/Under"),
    under45:val(4, "Under 4.5", "Goals Over/Under"),

    // ID 5 — Goals Odd/Even
    goalsOdd:  val(5, "Odd",  "Goals Odd/Even"),
    goalsEven: val(5, "Even", "Goals Odd/Even"),

    // ID 6 — Home Team Goals Over/Under
    homeOver05: val(6, "Over 0.5"),
    homeUnder05:val(6, "Under 0.5"),
    homeOver15: val(6, "Over 1.5"),
    homeUnder15:val(6, "Under 1.5"),
    homeOver25: val(6, "Over 2.5"),
    homeUnder25:val(6, "Under 2.5"),

    // ID 7 — Away Team Goals Over/Under
    awayOver05: val(7, "Over 0.5"),
    awayUnder05:val(7, "Under 0.5"),
    awayOver15: val(7, "Over 1.5"),
    awayUnder15:val(7, "Under 1.5"),
    awayOver25: val(7, "Over 2.5"),
    awayUnder25:val(7, "Under 2.5"),

    // ID 8 — Both Teams Score - First Half
    bttsFirstHalf: val(8, "Yes", "Both Teams To Score - First Half"),

    // ID 9 — Both Teams Score - Second Half
    bttsSecondHalf: val(9, "Yes", "Both Teams To Score - Second Half"),

    // ID 10 — First Half Winner
    htHomeWin: val(10, "Home", "First Half Winner"),
    htDraw:    val(10, "Draw", "First Half Winner"),
    htAwayWin: val(10, "Away", "First Half Winner"),

    // ID 11 — Second Half Winner
    shHomeWin: val(11, "Home", "Second Half Winner"),
    shDraw:    val(11, "Draw", "Second Half Winner"),
    shAwayWin: val(11, "Away", "Second Half Winner"),

    // ID 12 — Double Chance
    homeOrDraw: val(12, "Home/Draw", "Double Chance"),
    awayOrDraw: val(12, "Draw/Away", "Double Chance"),
    homeOrAway: val(12, "Home/Away", "Double Chance"),

    // ID 13 — Draw No Bet
    dnbHome: val(13, "Home", "Draw No Bet"),
    dnbAway: val(13, "Away", "Draw No Bet"),

    // ID 14 — First Team to Score
    firstTeamHome: val(14, "Home", "First Team to Score"),
    firstTeamAway: val(14, "Away", "First Team to Score"),
    firstTeamNone: val(14, "No Goal", "First Team to Score"),

    // ID 15 — Last Team to Score
    lastTeamHome: val(15, "Home", "Last Team to Score"),
    lastTeamAway: val(15, "Away", "Last Team to Score"),

    // ID 16 — Correct Score (Full Time)
    correctScores: (() => {
      const b = bet(16, "Correct Score");
      if (!b) return [];
      return b.values
        .map(v => ({ score: v.value, odd: parseFloat(v.odd) || 0 }))
        .filter(v => v.odd > 0 && v.odd < 20)
        .sort((a, b) => a.odd - b.odd)
        .slice(0, 10);
    })(),

    // ID 17 — Asian Handicap
    ahHome05: val(17, "Home -0.5", "Asian Handicap"),
    ahAway05: val(17, "Away -0.5", "Asian Handicap"),
    ahHome15: val(17, "Home -1.5", "Asian Handicap"),
    ahAway15: val(17, "Away -1.5", "Asian Handicap"),

    // ID 18 — Win to Nil
    homeWinToNil: val(18, "Home", "Win to Nil"),
    awayWinToNil: val(18, "Away", "Win to Nil"),

    // ID 19 — Both Teams Score & Winner
    bttsAndHomeWin: val(19, "Yes/Home", "Both Teams Score & Win") || val(19, "Home/Yes"),
    bttsAndDraw:    val(19, "Yes/Draw") || val(19, "Draw/Yes"),
    bttsAndAwayWin: val(19, "Yes/Away", "Both Teams Score & Win") || val(19, "Away/Yes"),

    // ID 20 — Exact Goals Number
    exactGoals0:    val(20, "0",  "Exact Goals Number"),
    exactGoals1:    val(20, "1",  "Exact Goals Number"),
    exactGoals2:    val(20, "2",  "Exact Goals Number"),
    exactGoals3:    val(20, "3",  "Exact Goals Number"),
    exactGoals4:    val(20, "4",  "Exact Goals Number"),
    exactGoals5plus:val(20, "5+", "Exact Goals Number"),

    // ID 21 — Clean Sheet
    homeCleanSheet: val(21, "Home", "Clean Sheet"),
    awayCleanSheet: val(21, "Away", "Clean Sheet"),

    // ID 22 — HT/FT
    htftHomeHome: val(22, "Home/Home", "HT/FT"),
    htftDrawHome: val(22, "Draw/Home", "HT/FT"),
    htftAwayHome: val(22, "Away/Home", "HT/FT"),
    htftHomeDraw: val(22, "Home/Draw", "HT/FT"),
    htftDrawDraw: val(22, "Draw/Draw", "HT/FT"),
    htftAwayDraw: val(22, "Away/Draw", "HT/FT"),
    htftHomeAway: val(22, "Home/Away", "HT/FT"),
    htftDrawAway: val(22, "Draw/Away", "HT/FT"),
    htftAwayAway: val(22, "Away/Away", "HT/FT"),

    // ID 23 — Total Corners
    cornersOver75:  val(23, "Over 7.5",  "Total Corners"),
    cornersUnder75: val(23, "Under 7.5", "Total Corners"),
    cornersOver85:  val(23, "Over 8.5",  "Total Corners"),
    cornersUnder85: val(23, "Under 8.5", "Total Corners"),
    cornersOver95:  val(23, "Over 9.5",  "Total Corners"),
    cornersUnder95: val(23, "Under 9.5", "Total Corners"),
    cornersOver105: val(23, "Over 10.5", "Total Corners"),
    cornersUnder105:val(23, "Under 10.5","Total Corners"),

    // ID 24 — Both Teams Score in Both Halves
    bttsBothHalves: val(24, "Yes", "Both Teams Score in Both Halves"),

    // ID 25 — Total Shots
    shotsOver85:   val(25, "Over 8.5",  "Total Shots"),
    shotsUnder85:  val(25, "Under 8.5", "Total Shots"),
    shotsOver105:  val(25, "Over 10.5", "Total Shots"),
    shotsUnder105: val(25, "Under 10.5","Total Shots"),
    shotsOver125:  val(25, "Over 12.5", "Total Shots"),
    shotsUnder125: val(25, "Under 12.5","Total Shots"),

    // ID 26 — Player First Goalscorer
    playerFirstGoal: playerList(26, "First Goalscorer"),

    // ID 27 — Player Last Goalscorer
    playerLastGoal: playerList(27, "Last Goalscorer"),

    // ID 28 — Player Anytime Goalscorer
    playerAnytime: playerList(28, "Anytime Goalscorer"),

    // ID 29 — Player to be Carded
    playerToBeCarded: playerList(29, "Player To Be Carded"),

    // ID 30 — Player to Assist
    playerToAssist: playerList(30, "Player To Assist"),

    // ID 31 — Player Shots on Target
    playerShotsOnTarget: playerList(31, "Player Shots on Target", 10),

    // ID 32 — Player to be Fouled
    playerToBeFouled: playerList(32, "Player To Be Fouled"),

    // ID 33 — Score in Both Halves (one team scores in both)
    homeScoreBothHalves: val(33, "Home", "Score in Both Halves"),
    awayScoreBothHalves: val(33, "Away", "Score in Both Halves"),

    // ID 34 — Home Team Goals Odd/Even
    homeGoalsOdd:  val(34, "Odd"),
    homeGoalsEven: val(34, "Even"),

    // ID 35 — Away Team Goals Odd/Even
    awayGoalsOdd:  val(35, "Odd"),
    awayGoalsEven: val(35, "Even"),

    // ID 37 — Winning Margin
    winMarginHome1: val(37, "Home by 1"),
    winMarginHome2: val(37, "Home by 2"),
    winMarginHome3: val(37, "Home by 3+") || val(37, "Home by 3"),
    winMarginAway1: val(37, "Away by 1"),
    winMarginAway2: val(37, "Away by 2"),
    winMarginAway3: val(37, "Away by 3+") || val(37, "Away by 3"),
    winMarginDraw:  val(37, "Draw"),

    // ID 45 — Correct Score First Half
    correctScoresHT: (() => {
      const b = bet(45, "Correct Score - First Half");
      if (!b) return [];
      return b.values
        .map(v => ({ score: v.value, odd: parseFloat(v.odd) || 0 }))
        .filter(v => v.odd > 0 && v.odd < 25)
        .sort((a, b) => a.odd - b.odd)
        .slice(0, 8);
    })(),

    // ID 62 — Correct Score Second Half
    correctScoresSH: (() => {
      const b = bet(62, "Correct Score - Second Half");
      if (!b) return [];
      return b.values
        .map(v => ({ score: v.value, odd: parseFloat(v.odd) || 0 }))
        .filter(v => v.odd > 0 && v.odd < 25)
        .sort((a, b) => a.odd - b.odd)
        .slice(0, 8);
    })(),

    // Legacy fields kept for existing features
    playerToBeScored2: playerList(28, "Player To Score 2+ Goals", 8),
    playerHatTrick:    playerList(28, "Player To Score Hat-trick", 8),

    // First Half Corners (from Total Corners first half variant)
    htCornersOver35:  val(23, "Over 3.5") || val(34, "Over 3.5"),
    htCornersUnder35: val(23, "Under 3.5") || val(34, "Under 3.5"),
    htCornersOver45:  val(23, "Over 4.5") || val(34, "Over 4.5"),
    htCornersUnder45: val(23, "Under 4.5") || val(34, "Under 4.5"),

    // Cards (ID 33 used by some bookmakers for bookings)
    cardsOver15:  val(33, "Over 1.5")  || null,
    cardsUnder15: val(33, "Under 1.5") || null,
    cardsOver25:  val(33, "Over 2.5")  || null,
    cardsUnder25: val(33, "Under 2.5") || null,
    cardsOver35:  val(33, "Over 3.5")  || null,
    cardsUnder35: val(33, "Under 3.5") || null,
    cardsOver45:  val(33, "Over 4.5")  || null,
    cardsUnder45: val(33, "Under 4.5") || null,

    // Offsides
    offsidesOver15:  null, offsidesUnder15: null,
    offsidesOver25:  null, offsidesUnder25: null,
  };

  // Also try name-based fallback for cards in case bookmaker uses "Total Bookings"
  if (!odds.cardsOver25) {
    odds.cardsOver15  = val(null, "Over 1.5",  "Total Bookings");
    odds.cardsUnder15 = val(null, "Under 1.5", "Total Bookings");
    odds.cardsOver25  = val(null, "Over 2.5",  "Total Bookings");
    odds.cardsUnder25 = val(null, "Under 2.5", "Total Bookings");
    odds.cardsOver35  = val(null, "Over 3.5",  "Total Bookings");
    odds.cardsUnder35 = val(null, "Under 3.5", "Total Bookings");
    odds.cardsOver45  = val(null, "Over 4.5",  "Total Bookings");
    odds.cardsUnder45 = val(null, "Under 4.5", "Total Bookings");
  }

  // First Half Goals — try both ID-based and name-based
  odds.htOver05  = val(null, "Over 0.5",  "First Half Goals");
  odds.htUnder05 = val(null, "Under 0.5", "First Half Goals");
  odds.htOver15  = val(null, "Over 1.5",  "First Half Goals");
  odds.htUnder15 = val(null, "Under 1.5", "First Half Goals");

  return odds;
}

async function fetchOddsForFixture(fixtureId) {
  const cached = getCachedOdds(fixtureId);
  if (cached) return cached;
  try {
    const headers = { "x-apisports-key": process.env.API_FOOTBALL_KEY };
    for (const bookmaker of [8, 1, 6, 10]) {
      const res  = await fetch(`${API_FOOTBALL_BASE}/odds?fixture=${fixtureId}&bookmaker=${bookmaker}`, { headers });
      const data = await res.json();
      const bets = data.response?.[0]?.bookmakers?.[0]?.bets || [];
      if (bets.length > 0) {
        const o = parseBets(bets); setCachedOdds(fixtureId, o); return o;
      }
    }
    const res  = await fetch(`${API_FOOTBALL_BASE}/odds?fixture=${fixtureId}`, { headers });
    const data = await res.json();
    const bets = data.response?.[0]?.bookmakers?.[0]?.bets || [];
    if (bets.length > 0) {
      const o = parseBets(bets); setCachedOdds(fixtureId, o); return o;
    }
    setCachedOdds(fixtureId, null); return null;
  } catch (err) {
    console.warn(`⚠️ Odds failed for ${fixtureId}: ${err.message}`); return null;
  }
}

async function fetchOddsInBatches(fixtures, batchSize = 12) {
  const results = [];
  for (let i = 0; i < fixtures.length; i += batchSize) {
    const batch = await Promise.all(fixtures.slice(i,i+batchSize).map(f => fetchOddsForFixture(f.fixture.id)));
    results.push(...batch);
    if (i+batchSize < fixtures.length) await new Promise(r => setTimeout(r, 200));
  }
  return results;
}

function mapFixture(f, odds = null) {
  return {
    fixtureId: f.fixture.id, home: f.teams.home.name, away: f.teams.away.name,
    status: f.fixture.status.short, elapsed: f.fixture.status.elapsed ?? null,
    homeGoals: f.goals.home??0, awayGoals: f.goals.away??0,
    competition: f.league.name, league_id: f.league.id, date: f.fixture.date,
    homeLogo: f.teams.home.logo, awayLogo: f.teams.away.logo,
    venue: f.fixture.venue?.name ?? null,
    isLive: LIVE_STATUSES.includes(f.fixture.status.short),
    isFinished: FINISH_STATUSES.includes(f.fixture.status.short),
    odds,
  };
}

async function buildMatchList() {
  if (!matchCache.isStale()) { console.log("⚡ Cache hit"); return matchCache.data; }
  console.log("🔄 Rebuilding match list...");
  const today  = new Date().toISOString().split("T")[0];
  const next60 = new Date(Date.now()+60*86400000).toISOString().split("T")[0];
  const now    = new Date();
  const season = now.getMonth()<7?now.getFullYear()-1:now.getFullYear();
  const results = await Promise.all(TOP_LEAGUE_IDS.map(id=>fetchFixtures({league:id,season,from:today,to:next60}).catch(()=>[])));
  const all = results.flat();
  const seen = new Set();
  const unique = all.filter(f=>{if(seen.has(f.fixture.id))return false;seen.add(f.fixture.id);return true;});
  console.log(`✅ ${unique.length} fixtures — fetching odds...`);
  const oddsResults = await fetchOddsInBatches(unique);
  console.log(`✅ Odds: ${oddsResults.filter(Boolean).length}/${unique.length}`);
  const liveMatches = unique.map((f,i)=>mapFixture(f,oddsResults[i])).sort((a,b)=>new Date(a.date)-new Date(b.date));
  matchCache.set(liveMatches);
  return liveMatches;
}

async function warmupCache() {
  console.log("🔥 Warming cache...");
  try { await buildMatchList(); console.log("✅ Cache warm"); }
  catch(err) { console.error("❌ Warmup failed:", err.message); }
}

// --- AUTO-RESOLVE ---
function evaluatePick(market, fixture) {
  const home=fixture.teams.home.name; const away=fixture.teams.away.name;
  const hg=fixture.goals.home??0; const ag=fixture.goals.away??0;
  const total=hg+ag;
  const htH=fixture.score?.halftime?.home??0; const htA=fixture.score?.halftime?.away??0;
  if(!FINISH_STATUSES.includes(fixture.fixture.status.short)) return null;
  const m=market.toLowerCase();
  if(m===`${home.toLowerCase()} win`) return hg>ag?"correct":"wrong";
  if(m==="draw") return hg===ag?"correct":"wrong";
  if(m===`${away.toLowerCase()} win`) return ag>hg?"correct":"wrong";
  if(m.includes("or draw")&&m.includes(home.toLowerCase())) return hg>=ag?"correct":"wrong";
  if(m.includes("or draw")&&m.includes(away.toLowerCase())) return ag>=hg?"correct":"wrong";
  if(m==="either team wins") return hg!==ag?"correct":"wrong";
  const under=m.match(/fewer than (\d+)/);
  if(under) return total<parseInt(under[1])?"correct":"wrong";
  const over=m.match(/^(\d+)\+ goals?/);
  if(over) return total>=parseInt(over[1])?"correct":"wrong";
  const exact=m.match(/^exactly (\d+)/);
  if(exact) return total===parseInt(exact[1])?"correct":"wrong";
  if(m==="5 or more goals") return total>=5?"correct":"wrong";
  const htTotal=htH+htA;
  if(m.includes("no")&&m.includes("first-half")) return htTotal===0?"correct":"wrong";
  if(m.includes("1+")&&m.includes("first-half")) return htTotal>=1?"correct":"wrong";
  if(m.includes("2+")&&m.includes("first-half")) return htTotal>=2?"correct":"wrong";
  if((m.includes("both")&&m.includes("score")&&m.startsWith("yes"))||m==="yes — both score") return hg>0&&ag>0?"correct":"wrong";
  if((m.includes("both")&&(m.startsWith("no")||m.includes("blank")))||m==="no — one blank") return hg===0||ag===0?"correct":"wrong";
  if(m.includes("leading")&&m.includes(home.toLowerCase())) return htH>htA?"correct":"wrong";
  if(m.includes("level at")) return htH===htA?"correct":"wrong";
  if(m.includes("leading")&&m.includes(away.toLowerCase())) return htA>htH?"correct":"wrong";
  if(m.includes("win")&&m.includes("clean sheet")&&m.includes(home.toLowerCase())) return hg>ag&&ag===0?"correct":"wrong";
  if(m.includes("win")&&m.includes("clean sheet")&&m.includes(away.toLowerCase())) return ag>hg&&hg===0?"correct":"wrong";
  if(m.includes("clean sheet")&&m.includes(home.toLowerCase())) return ag===0?"correct":"wrong";
  if(m.includes("clean sheet")&&m.includes(away.toLowerCase())) return hg===0?"correct":"wrong";
  const score=m.match(/^(\d+)-(\d+)$/);
  if(score) return parseInt(score[1])===hg&&parseInt(score[2])===ag?"correct":"wrong";
  // Odd/Even
  if(m==="goals odd")  return total%2!==0?"correct":"wrong";
  if(m==="goals even") return total%2===0?"correct":"wrong";
  if(m.includes("home team")&&m.includes("odd"))  return hg%2!==0?"correct":"wrong";
  if(m.includes("home team")&&m.includes("even")) return hg%2===0?"correct":"wrong";
  if(m.includes("away team")&&m.includes("odd"))  return ag%2!==0?"correct":"wrong";
  if(m.includes("away team")&&m.includes("even")) return ag%2===0?"correct":"wrong";
  // Second half winner
  const shH=(fixture.goals.home??0)-(fixture.score?.halftime?.home??0);
  const shA=(fixture.goals.away??0)-(fixture.score?.halftime?.away??0);
  if(m.includes("2nd half")&&m.includes(home.toLowerCase())) return shH>shA?"correct":"wrong";
  if(m.includes("2nd half")&&m.includes("draw")) return shH===shA?"correct":"wrong";
  if(m.includes("2nd half")&&m.includes(away.toLowerCase())) return shA>shH?"correct":"wrong";
  return null;
}

async function resolvePicksForMatch(fixture) {
  const{data:picks}=await supabaseAdmin.from("picks").select("*").eq("result","pending").ilike("match",`%${fixture.teams.home.name}%`);
  if(!picks?.length) return 0;
  let resolved=0;
  for(const pick of picks){
    if(!pick.match.toLowerCase().includes(fixture.teams.away.name.toLowerCase())) continue;
    const result=evaluatePick(pick.market,fixture);
    if(!result) continue;
    const prob=pick.probability||Math.min(99,Math.max(1,Math.round(100.0/(pick.odds||2.0))));
    const{data:profile}=await supabaseAdmin.from("profiles").select("*").eq("id",pick.user_id).single();
    if(!profile) continue;
    let newStreak=0,finalPoints=0;
    if(result==="correct"){newStreak=(profile.current_streak||0)+1;finalPoints=Math.round(calcPointsWin(prob)*getStreakMultiplier(newStreak)*getDailyBonus(profile.daily_streak));}
    else{finalPoints=-calcPointsLoss(prob);}
    const du=updateDailyStreak(profile);
    await supabaseAdmin.from("picks").update({result,points_earned:finalPoints}).eq("id",pick.id);
    await supabaseAdmin.from("profiles").update({current_streak:result==="correct"?newStreak:0,best_streak:Math.max(profile.best_streak||0,newStreak),total_points:(profile.total_points||0)+finalPoints,weekly_points:(profile.weekly_points||0)+finalPoints,daily_streak:du.daily_streak,best_daily_streak:du.best_daily_streak,last_pick_date:du.last_pick_date}).eq("id",pick.user_id);
    resolved++;
  }
  return resolved;
}

// --- ROUTES ---
app.get("/", (req,res)=>res.send("Predkt API is Live"));

app.get("/api/live", async(req,res)=>{
  try{const fixtures=await fetchFixtures({live:"all"});res.json({liveMatches:fixtures.map(f=>mapFixture(f))});}
  catch(err){res.status(500).json({error:err.message});}
});

app.get("/api/matches", async(req,res)=>{
  try{res.json({liveMatches:await buildMatchList()});}
  catch(err){console.error("❌",err.message);res.status(500).json({error:err.message});}
});

app.post("/api/refresh-cache", requireAdmin, async(req,res)=>{
  matchCache.invalidate();oddsCache.clear();
  try{await buildMatchList();res.json({ok:true});}
  catch(err){res.status(500).json({error:err.message});}
});

app.post("/api/auto-resolve", async(req,res)=>{
  try{
    const headers={"x-apisports-key":process.env.API_FOOTBALL_KEY};
    const fixtures=(await(await fetch(`${API_FOOTBALL_BASE}/fixtures?status=FT&last=50`,{headers})).json()).response||[];
    let total=0;
    for(const f of fixtures){total+=await resolvePicksForMatch(f);}
    res.json({ok:true,resolved:total});
  }catch(err){res.status(500).json({error:err.message});}
});

app.post("/api/resolve", requireAdmin, async(req,res)=>{
  const{pickId,result}=req.body;
  const{data:pick}=await supabaseAdmin.from("picks").select("*").eq("id",pickId).single();
  const{data:profile}=await supabaseAdmin.from("profiles").select("*").eq("id",pick.user_id).single();
  const prob=pick.probability||Math.min(99,Math.max(1,Math.round(100.0/(pick.odds||2.0))));
  let newStreak=0,finalPoints=0;
  if(result==="correct"){newStreak=(profile.current_streak||0)+1;finalPoints=Math.round(calcPointsWin(prob)*getStreakMultiplier(newStreak)*getDailyBonus(profile.daily_streak));}
  else{finalPoints=-calcPointsLoss(prob);}
  const du=updateDailyStreak(profile);
  await supabaseAdmin.from("picks").update({result,points_earned:finalPoints}).eq("id",pickId);
  await supabaseAdmin.from("profiles").update({current_streak:result==="correct"?newStreak:0,best_streak:Math.max(profile.best_streak||0,newStreak),total_points:(profile.total_points||0)+finalPoints,weekly_points:(profile.weekly_points||0)+finalPoints,daily_streak:du.daily_streak,best_daily_streak:du.best_daily_streak,last_pick_date:du.last_pick_date}).eq("id",pick.user_id);
  res.json({ok:true,points_earned:finalPoints});
});

app.post("/api/weekly-reset", requireAdmin, async(req,res)=>{
  try{await supabaseAdmin.rpc("reset_weekly_points");res.json({ok:true});}
  catch(err){res.status(500).json({error:err.message});}
});

cron.schedule("*/15 * * * *", async()=>{
  try{
    const headers={"x-apisports-key":process.env.API_FOOTBALL_KEY};
    const fixtures=(await(await fetch(`${API_FOOTBALL_BASE}/fixtures?status=FT&last=50`,{headers})).json()).response||[];
    let total=0;for(const f of fixtures){total+=await resolvePicksForMatch(f);}
    if(total>0) console.log(`⏰ Auto-resolved ${total} picks`);
  }catch(err){console.error("❌ Auto-resolve:",err.message);}
});

cron.schedule("*/30 * * * *", async()=>{
  matchCache.invalidate();
  try{await buildMatchList();console.log("✅ Cache refreshed");}
  catch(err){console.error("❌ Cache refresh:",err.message);}
});

cron.schedule("0 0 * * 1", async()=>{
  try{await supabaseAdmin.rpc("reset_weekly_points");console.log("✅ Weekly reset");}
  catch(err){console.error("❌ Weekly reset:",err.message);}
});

const PORT=process.env.PORT||8080;
app.listen(PORT,"0.0.0.0",async()=>{
  console.log(`✅ SERVER on port ${PORT}`);
  setTimeout(warmupCache,2000);
});
// Debug route — no auth, no cache, just fetches one league
app.get("/api/debug", async (req, res) => {
  try {
    const headers = { "x-apisports-key": process.env.API_FOOTBALL_KEY };

    // 1. Check API key exists
    if (!process.env.API_FOOTBALL_KEY) {
      return res.json({ error: "API_FOOTBALL_KEY is missing" });
    }

    // 2. Try fetching just Premier League fixtures
    const url = `${API_FOOTBALL_BASE}/fixtures?league=39&season=2025&next=5`;
    const response = await fetch(url, { headers });
    const data = await response.json();

    res.json({
      apiKeyPresent: !!process.env.API_FOOTBALL_KEY,
      apiKeyPrefix: process.env.API_FOOTBALL_KEY?.slice(0, 6) + "...",
      fixturesFound: data.response?.length ?? 0,
      apiError: data.errors ?? null,
      sampleFixture: data.response?.[0]?.fixture?.date ?? "none",
      cacheIsStale: matchCache.isStale(),
      cachedMatchCount: matchCache.data?.length ?? 0,
    });
  } catch (err) {
    res.json({ error: err.message });
  }
});