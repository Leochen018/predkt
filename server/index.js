require("dotenv").config();
const express     = require("express");
const cors        = require("cors");
const cron        = require("node-cron");
const { createClient } = require("@supabase/supabase-js");

const app = express();
app.use(cors());
app.use(express.json());

const SB_URL         = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
const SB_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;
const SB_ANON_KEY    = process.env.SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const supabaseAdmin    = createClient(SB_URL, SB_SERVICE_KEY);
const supabaseStandard = createClient(SB_URL, SB_ANON_KEY);
const API_BASE = "https://v3.football.api-sports.io";

// ── CACHE ─────────────────────────────────────────────────────────────────────
const matchCache = {
  data: null, builtAt: null,
  ttl: 2 * 60 * 60 * 1000,
  isStale() { return !this.data || !this.builtAt || Date.now() - this.builtAt > this.ttl; },
  set(data)  { this.data = data; this.builtAt = Date.now(); console.log(`✅ Cache: ${data.length} matches`); },
  invalidate(){ this.data = null; this.builtAt = null; }
};

const oddsCache = new Map();
const ODDS_TTL  = 12 * 60 * 60 * 1000;
function getCachedOdds(id) {
  const e = oddsCache.get(id);
  if (!e || Date.now() - e.cachedAt > ODDS_TTL) { oddsCache.delete(id); return undefined; }
  return e.odds;
}
function setCachedOdds(id, odds) { oddsCache.set(id, { odds, cachedAt: Date.now() }); }

// ── SCORING ───────────────────────────────────────────────────────────────────
function calcPointsWin(p)       { return Math.max(1, 10 + (100 - Math.min(99, Math.max(1, parseInt(p)||50)))); }
function calcPointsLoss(p)      { return Math.max(1, Math.round(calcPointsWin(p)/2)); }
function getStreakMultiplier(s) { return Math.min(1.0 + Math.max(0, parseInt(s)||0) * 0.1, 2.0); }
function getDailyBonus(d)       { return (parseInt(d)||0) >= 2 ? 1.2 : 1.0; }
function updateDailyStreak(p) {
  const today = new Date().toISOString().split("T")[0];
  if (p.last_pick_date === today) return { ...p, dailyStreakChanged: false };
  const yesterday = new Date(); yesterday.setDate(yesterday.getDate()-1);
  const newDaily = p.last_pick_date === yesterday.toISOString().split("T")[0] ? (p.daily_streak||0)+1 : 1;
  return { daily_streak: newDaily, best_daily_streak: Math.max(p.best_daily_streak||0, newDaily), last_pick_date: today };
}

async function requireAdmin(req, res, next) {
  const auth = req.headers.authorization;
  if (!auth?.startsWith("Bearer ")) return res.status(401).json({ error: "Unauthorized" });
  const { data: { user }, error } = await supabaseStandard.auth.getUser(auth.split(" ")[1]);
  if (error || !user || user.id !== process.env.ADMIN_USER_ID) return res.status(403).json({ error: "Forbidden" });
  next();
}

// ── CONSTANTS ─────────────────────────────────────────────────────────────────
const TOP_LEAGUES = [
  // ── ENGLAND ───────────────────────────────────────────────────────────────
  { id: 39,  name: "Premier League"      },
  { id: 40,  name: "Championship"        },
  { id: 41,  name: "League One"          },
  { id: 45,  name: "FA Cup"              },
  { id: 48,  name: "EFL Cup"             },

  // ── EUROPE ────────────────────────────────────────────────────────────────
  { id: 2,   name: "Champions League"    },
  { id: 3,   name: "Europa League"       },
  { id: 848, name: "Conference League"   },

  // ── SPAIN ─────────────────────────────────────────────────────────────────
  { id: 140, name: "La Liga"             },
  { id: 141, name: "La Liga 2"           },
  { id: 143, name: "Copa del Rey"        },

  // ── ITALY ─────────────────────────────────────────────────────────────────
  { id: 135, name: "Serie A"             },
  { id: 136, name: "Serie B"             },
  { id: 137, name: "Coppa Italia"        },

  // ── GERMANY ───────────────────────────────────────────────────────────────
  { id: 78,  name: "Bundesliga"          },
  { id: 79,  name: "Bundesliga 2"        },
  { id: 81,  name: "DFB Pokal"           },

  // ── FRANCE ────────────────────────────────────────────────────────────────
  { id: 61,  name: "Ligue 1"             },
  { id: 62,  name: "Ligue 2"             },
  { id: 66,  name: "Coupe de France"     },

  // ── PORTUGAL ──────────────────────────────────────────────────────────────
  { id: 94,  name: "Primeira Liga"       },
  { id: 95,  name: "Segunda Liga"        },

  // ── NETHERLANDS ───────────────────────────────────────────────────────────
  { id: 88,  name: "Eredivisie"          },
  { id: 89,  name: "Eerste Divisie"      },

  // ── TURKEY ────────────────────────────────────────────────────────────────
  { id: 203, name: "Super Lig"           },

  // ── SCOTLAND ──────────────────────────────────────────────────────────────
  { id: 179, name: "Scottish Premiership"},

  // ── BELGIUM ───────────────────────────────────────────────────────────────
  { id: 144, name: "Pro League"          },

  // ── INTERNATIONAL ─────────────────────────────────────────────────────────
  { id: 1,   name: "World Cup"           },
  { id: 4,   name: "Euro Championship"   },
  { id: 9,   name: "Nations League"      },
  { id: 10,  name: "Friendlies"          },
];
const LEAGUE_IDS      = TOP_LEAGUES.map(l => l.id);
const LIVE_STATUSES   = ["1H","HT","2H","ET","BT","P","LIVE","INT"];
const FINISH_STATUSES = ["FT","AET","PEN","WO","AWD","ABD"];

// ── DATE HELPERS ──────────────────────────────────────────────────────────────
function dateStr(offsetDays = 0) {
  const d = new Date();
  d.setDate(d.getDate() + offsetDays);
  return d.toISOString().split("T")[0];
}
function currentSeason() {
  const now = new Date();
  return now.getMonth() >= 7 ? now.getFullYear() : now.getFullYear() - 1;
}

// ── API FETCH ─────────────────────────────────────────────────────────────────
async function apiFetch(path, params = {}) {
  const headers = { "x-apisports-key": process.env.API_FOOTBALL_KEY };
  const url     = `${API_BASE}${path}?${new URLSearchParams(params)}`;
  try {
    const res  = await fetch(url, { headers, signal: AbortSignal.timeout(15000) });
    const data = await res.json();
    if (data.errors && Object.keys(data.errors).length) {
      console.warn(`⚠️ [${path}]:`, JSON.stringify(data.errors));
    }
    return data.response || [];
  } catch (err) {
    console.warn(`⚠️ apiFetch [${path}]:`, err.message);
    return [];
  }
}

async function fetchLeagueFixtures(leagueId) {
  const season = currentSeason();
  const from   = dateStr(-1);
  const to     = dateStr(30);
  const fixtures = await apiFetch("/fixtures", { league: leagueId, season, from, to });
  console.log(`  League ${leagueId}: ${fixtures.length} fixtures`);
  return fixtures;
}

// ── PARSE ODDS ────────────────────────────────────────────────────────────────
function parseBets(bets) {
  const byId   = (id)   => bets.find(b => b.id === id);
  const byName = (name) => bets.find(b => b.name === name);
  const bet    = (id, fb) => (id ? byId(id) : null) || (fb ? byName(fb) : null);
  const val    = (id, v, fb) => { const b=bet(id,fb); return parseFloat(b?.values?.find(x=>x.value===v)?.odd)||null; };

  const sList  = (id, fb, mx=20, n=10) => {
    const b=bet(id,fb);
    if(!b) return [];
    return b.values
      .map(v=>({score:v.value, odd:parseFloat(v.odd)||0}))
      .filter(v=>v.odd>0 && v.odd<mx)
      .sort((a,b)=>a.odd-b.odd)
      .slice(0,n);
  };

  // ✅ pList: reads player name from v.value and cleans it up
  // API-Football returns player names directly in the value field
  // e.g. { value: "Erling Haaland", odd: "3.50" }
  const pList = (id, fb, n=14) => {
    const b = bet(id, fb);
    if (!b) return [];
    return b.values
      .map(v => {
        // Clean the name — strip any "Home: " or "Away: " prefixes some bookmakers add
        const rawName = v.value || "";
        const name = rawName
          .replace(/^(Home|Away):\s*/i, "")
          .trim();
        return { name, odd: parseFloat(v.odd) || 0 };
      })
      .filter(v => v.odd > 1 && v.name.length > 1)
      .sort((a, b) => a.odd - b.odd)
      .slice(0, n);
  };
  // Fuzzy name search — bookmakers use different names for the same market
const pListAny = (keywords, n = 8) => {
    for (const kw of keywords) {
        const b = bets.find(b => b.name?.toLowerCase().includes(kw.toLowerCase()));
        if (b?.values?.length > 0) {
            return b.values
                .map(v => ({
                    name: (v.value || "").replace(/^(Home|Away):\s*/i, "").trim(),
                    odd: parseFloat(v.odd) || 0
                }))
                .filter(v => v.odd > 1 && v.name.length > 1)
                .sort((a, b) => a.odd - b.odd)
                .slice(0, n);
        }
    }
    return [];
};
  return {
    homeWin:val(1,"Home","Match Winner"), draw:val(1,"Draw","Match Winner"), awayWin:val(1,"Away","Match Winner"),
    homeWinNoDraw:val(2,"Home","Home/Away"), awayWinNoDraw:val(2,"Away","Home/Away"),
    bttsYes:val(3,"Yes","Both Teams Score"), bttsNo:val(3,"No","Both Teams Score"),
    over05:val(4,"Over 0.5","Goals Over/Under"),  under05:val(4,"Under 0.5","Goals Over/Under"),
    over15:val(4,"Over 1.5","Goals Over/Under"),  under15:val(4,"Under 1.5","Goals Over/Under"),
    over25:val(4,"Over 2.5","Goals Over/Under"),  under25:val(4,"Under 2.5","Goals Over/Under"),
    over35:val(4,"Over 3.5","Goals Over/Under"),  under35:val(4,"Under 3.5","Goals Over/Under"),
    over45:val(4,"Over 4.5","Goals Over/Under"),  under45:val(4,"Under 4.5","Goals Over/Under"),
    goalsOdd:val(5,"Odd","Goals Odd/Even"), goalsEven:val(5,"Even","Goals Odd/Even"),
    homeOver05:val(6,"Over 0.5"), homeUnder05:val(6,"Under 0.5"),
    homeOver15:val(6,"Over 1.5"), homeUnder15:val(6,"Under 1.5"),
    homeOver25:val(6,"Over 2.5"), homeUnder25:val(6,"Under 2.5"),
    awayOver05:val(7,"Over 0.5"), awayUnder05:val(7,"Under 0.5"),
    awayOver15:val(7,"Over 1.5"), awayUnder15:val(7,"Under 1.5"),
    awayOver25:val(7,"Over 2.5"), awayUnder25:val(7,"Under 2.5"),
    bttsFirstHalf:val(8,"Yes","Both Teams To Score - First Half"),
    bttsSecondHalf:val(9,"Yes","Both Teams To Score - Second Half"),
    htHomeWin:val(10,"Home","First Half Winner"), htDraw:val(10,"Draw","First Half Winner"), htAwayWin:val(10,"Away","First Half Winner"),
    shHomeWin:val(11,"Home","Second Half Winner"), shDraw:val(11,"Draw","Second Half Winner"), shAwayWin:val(11,"Away","Second Half Winner"),
    homeOrDraw:val(12,"Home/Draw","Double Chance"), awayOrDraw:val(12,"Draw/Away","Double Chance"), homeOrAway:val(12,"Home/Away","Double Chance"),
    dnbHome:val(13,"Home","Draw No Bet"), dnbAway:val(13,"Away","Draw No Bet"),
    firstTeamHome:val(14,"Home","First Team to Score"), firstTeamAway:val(14,"Away","First Team to Score"), firstTeamNone:val(14,"No Goal","First Team to Score"),
    lastTeamHome:val(15,"Home","Last Team to Score"), lastTeamAway:val(15,"Away","Last Team to Score"),
    correctScores:sList(16,"Correct Score"),
    ahHome05:val(17,"Home -0.5","Asian Handicap"), ahAway05:val(17,"Away -0.5","Asian Handicap"),
    ahHome15:val(17,"Home -1.5","Asian Handicap"), ahAway15:val(17,"Away -1.5","Asian Handicap"),
    homeWinToNil:val(18,"Home","Win to Nil"), awayWinToNil:val(18,"Away","Win to Nil"),
    bttsAndHomeWin:val(19,"Yes/Home")||val(19,"Home/Yes"),
    bttsAndDraw:val(19,"Yes/Draw")||val(19,"Draw/Yes"),
    bttsAndAwayWin:val(19,"Yes/Away")||val(19,"Away/Yes"),
    exactGoals0:val(20,"0","Exact Goals Number"), exactGoals1:val(20,"1","Exact Goals Number"),
    exactGoals2:val(20,"2","Exact Goals Number"), exactGoals3:val(20,"3","Exact Goals Number"),
    exactGoals4:val(20,"4","Exact Goals Number"), exactGoals5plus:val(20,"5+","Exact Goals Number"),
    homeCleanSheet:val(21,"Home","Clean Sheet"), awayCleanSheet:val(21,"Away","Clean Sheet"),
    htftHomeHome:val(22,"Home/Home","HT/FT"), htftDrawHome:val(22,"Draw/Home","HT/FT"),
    htftAwayHome:val(22,"Away/Home","HT/FT"), htftHomeDraw:val(22,"Home/Draw","HT/FT"),
    htftDrawDraw:val(22,"Draw/Draw","HT/FT"), htftAwayDraw:val(22,"Away/Draw","HT/FT"),
    htftHomeAway:val(22,"Home/Away","HT/FT"), htftDrawAway:val(22,"Draw/Away","HT/FT"),
    htftAwayAway:val(22,"Away/Away","HT/FT"),
    cornersOver75:val(23,"Over 7.5","Total Corners"),   cornersUnder75:val(23,"Under 7.5","Total Corners"),
    cornersOver85:val(23,"Over 8.5","Total Corners"),   cornersUnder85:val(23,"Under 8.5","Total Corners"),
    cornersOver95:val(23,"Over 9.5","Total Corners"),   cornersUnder95:val(23,"Under 9.5","Total Corners"),
    cornersOver105:val(23,"Over 10.5","Total Corners"), cornersUnder105:val(23,"Under 10.5","Total Corners"),
    htCornersOver35:val(null,"Over 3.5","First Half Corners"),  htCornersUnder35:val(null,"Under 3.5","First Half Corners"),
    htCornersOver45:val(null,"Over 4.5","First Half Corners"),  htCornersUnder45:val(null,"Under 4.5","First Half Corners"),
    bttsBothHalves:val(24,"Yes","Both Teams Score in Both Halves"),
    shotsOver85:val(25,"Over 8.5","Total Shots"),   shotsUnder85:val(25,"Under 8.5","Total Shots"),
    shotsOver105:val(25,"Over 10.5","Total Shots"), shotsUnder105:val(25,"Under 10.5","Total Shots"),
    shotsOver125:val(25,"Over 12.5","Total Shots"), shotsUnder125:val(25,"Under 12.5","Total Shots"),
    // ✅ Player props — now using merged multi-bookmaker bets for full player lists
    playerFirstGoal:     pList(null, "First Goalscorer"),
    playerLastGoal:      pList(null, "Last Goalscorer"),
    playerAnytime:       pList(null, "Anytime Goalscorer"),
    playerToBeCarded:    pList(null, "Player To Be Carded"),
    playerToAssist:      pList(null, "Player To Assist"),
    playerShotsOnTarget: pList(null, "Player Shots on Target", 10),
    playerToBeFouled:    pList(null, "Player To Be Fouled"),
    playerToBeScored2:   pListAny(["2 or more goals", "brace scorer", "score 2+", "to score 2"], 8),
    playerHatTrick:      pListAny(["hat-trick", "hat trick", "3 or more goals", "score 3+", "to score 3"], 8),  
    homeScoreBothHalves:val(33,"Home","Score in Both Halves"),
    awayScoreBothHalves:val(33,"Away","Score in Both Halves"),
    cardsOver15:val(null,"Over 1.5","Total Bookings"),   cardsUnder15:val(null,"Under 1.5","Total Bookings"),
    cardsOver25:val(null,"Over 2.5","Total Bookings"),   cardsUnder25:val(null,"Under 2.5","Total Bookings"),
    cardsOver35:val(null,"Over 3.5","Total Bookings"),   cardsUnder35:val(null,"Under 3.5","Total Bookings"),
    cardsOver45:val(null,"Over 4.5","Total Bookings"),   cardsUnder45:val(null,"Under 4.5","Total Bookings"),
    homeGoalsOdd:val(34,"Odd"), homeGoalsEven:val(34,"Even"),
    awayGoalsOdd:val(35,"Odd"), awayGoalsEven:val(35,"Even"),
    winMarginHome1:val(37,"Home by 1"), winMarginHome2:val(37,"Home by 2"),
    winMarginHome3:val(37,"Home by 3+")||val(37,"Home by 3"),
    winMarginAway1:val(37,"Away by 1"), winMarginAway2:val(37,"Away by 2"),
    winMarginAway3:val(37,"Away by 3+")||val(37,"Away by 3"),
    winMarginDraw:val(37,"Draw"),
    correctScoresHT:sList(45,"Correct Score - First Half",25,8),
    correctScoresSH:sList(62,"Correct Score - Second Half",25,8),
    htOver05:val(null,"Over 0.5","First Half Goals"), htUnder05:val(null,"Under 0.5","First Half Goals"),
    htOver15:val(null,"Over 1.5","First Half Goals"), htUnder15:val(null,"Under 1.5","First Half Goals"),
  };
}

// ── FETCH ODDS ────────────────────────────────────────────────────────────────
// ✅ KEY FIX: Fetch from multiple bookmakers in parallel and MERGE their bets
// Previously stopped at first bookmaker with ANY data — missed player props
// Now merges all bookmakers: match markets from bm 8, player props from bm 2/4/7
async function fetchOddsForId(fixtureId) {
  const cached = getCachedOdds(fixtureId);
  if (cached !== undefined) return cached;

  try {
    const headers = { "x-apisports-key": process.env.API_FOOTBALL_KEY };

    // Bookmaker IDs:
    //   2  = Bet365       ← player props (anytime scorer, carded etc)
    //   4  = William Hill ← player props
    //   7  = Unibet       ← player props
    //   8  = Bet365 alt   ← match markets (1x2, goals, corners)
    //   1  = 10Bet        ← match markets fallback
    //   6  = Bwin         ← match markets fallback
    const bookmakerIds = [2, 4, 7, 8, 1, 6];

    const allBetsFromBookmakers = await Promise.all(
      bookmakerIds.map(bm =>
        fetch(`${API_BASE}/odds?fixture=${fixtureId}&bookmaker=${bm}`, {
          headers,
          signal: AbortSignal.timeout(8000),
        })
          .then(r => r.json())
          .then(data => data.response?.[0]?.bookmakers?.[0]?.bets || [])
          .catch(() => [])
      )
    );

    // Merge bets from all bookmakers
    // Key by bet ID (preferred) or bet name — keep version with most values
    const merged = new Map();
    for (const bets of allBetsFromBookmakers) {
      for (const bet of bets) {
        const key = bet.id ? `id_${bet.id}` : `name_${bet.name}`;
        const existing = merged.get(key);
        if (!existing) {
          merged.set(key, bet);
        } else {
          // Keep whichever has more player names / values
          if ((bet.values?.length || 0) > (existing.values?.length || 0)) {
            merged.set(key, bet);
          }
        }
      }
    }

    const allBets = Array.from(merged.values());

    if (allBets.length === 0) {
      setCachedOdds(fixtureId, null);
      return null;
    }

    // Log player prop coverage for debugging
    const playerBets = allBets.filter(b =>
      [26,27,28,29,30,31,32].includes(b.id) ||
      b.name?.includes("Goalscorer") || b.name?.includes("Player")
    );
    if (playerBets.length > 0) {
      const sample = playerBets[0]?.values?.slice(0,2).map(v=>v.value).join(", ");
      console.log(`  ⚽ ${fixtureId}: ${playerBets.length} player markets, e.g. "${sample}"`);
    }

    const odds = parseBets(allBets);
    setCachedOdds(fixtureId, odds);
    return odds;

  } catch (err) {
    console.warn(`  Odds error ${fixtureId}:`, err.message);
    return null;
  }
}

// ── GOAL EVENTS ───────────────────────────────────────────────────────────────
async function fetchGoalEvents(fixtureId) {
    try {
        const events = await apiFetch("/fixtures/events", { fixture: fixtureId });
        const counts = {};       // { "Erling Haaland": 2 }
        const scorerOrder = [];  // first → last goal scorer (name, in order)

        for (const e of events) {
            if (e.type !== "Goal" || e.detail === "Own Goal" || e.detail === "Penalty Missed") continue;
            const name = e.player?.name;
            if (!name) continue;
            counts[name] = (counts[name] || 0) + 1;
            scorerOrder.push(name);
        }

        return {
            counts,
            firstScorer: scorerOrder[0]  ?? null,
            lastScorer:  scorerOrder[scorerOrder.length - 1] ?? null,
        };
    } catch (err) {
        console.warn(`⚠️ fetchGoalEvents ${fixtureId}:`, err.message);
        return { counts: {}, firstScorer: null, lastScorer: null };
    }
}

// Fuzzy match "Haaland" or "Erling Haaland" against event names
function fuzzyMatch(pickName, eventNames) {
    const clean = pickName.toLowerCase()
        .replace(/\s*\(.*?\)\s*/g, "")  // strip "(anytime)", "(2+ goals)" etc
        .trim();
    for (const n of eventNames) {
        const en = n.toLowerCase();
        if (en === clean) return n;
        if (en.includes(clean) || clean.includes(en)) return n;
        const last = clean.split(" ").pop();
        if (last.length > 3 && en.includes(last)) return n;
    }
    return null;
}

function mapFixture(f, odds=null) {
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
    venue:       f.fixture.venue?.name ?? null,
    isLive:      LIVE_STATUSES.includes(f.fixture.status.short),
    isFinished:  FINISH_STATUSES.includes(f.fixture.status.short),
    odds,
  };
}

// ── BUILD MATCH LIST ──────────────────────────────────────────────────────────
async function buildMatchList() {
  if (!matchCache.isStale()) {
    console.log(`⚡ Cache hit (${matchCache.data.length} matches)`);
    return matchCache.data;
  }

  const season = currentSeason();
  console.log(`🔄 Building for season=${season}...`);

  const leagueResults = await Promise.all(
    LEAGUE_IDS.map(id => fetchLeagueFixtures(id))
  );

 console.log(`🔴 Skipping global live fetch — only showing TOP_LEAGUES`);

const seen   = new Set();
const unique = [...leagueResults.flat()].filter(f => {

    if (seen.has(f.fixture.id)) return false;
    seen.add(f.fixture.id); return true;
  });

  const days = [...new Set(unique.map(f=>f.fixture.date.slice(0,10)))].sort();
  console.log(`📋 ${unique.length} fixtures across ${days.length} days: ${days[0]} → ${days[days.length-1]}`);

  if (unique.length === 0) {
    console.error("❌ 0 fixtures — API limit hit");
    return matchCache.data || [];
  }

  const cutoff   = new Date(); cutoff.setDate(cutoff.getDate() + 7);
  const upcoming = unique.filter(f =>
    !LIVE_STATUSES.includes(f.fixture.status.short) &&
    !FINISH_STATUSES.includes(f.fixture.status.short) &&
    new Date(f.fixture.date) <= cutoff
  );
  const skipped = unique.length - upcoming.length;
  console.log(`🎰 Fetching odds for ${upcoming.length} fixtures (skipping ${skipped})`);

  const oddsResults = [];
  for (let i=0; i<upcoming.length; i+=6) {
    const batch = await Promise.all(upcoming.slice(i,i+6).map(f=>fetchOddsForId(f.fixture.id)));
    oddsResults.push(...batch);
    if (i+6<upcoming.length) await new Promise(r=>setTimeout(r,200));
  }

  const upcomingMap  = new Map(upcoming.map((f,i) => [f.fixture.id, oddsResults[i]]));
  const liveMatches  = unique
    .map(f => mapFixture(f, upcomingMap.get(f.fixture.id) ?? null))
    .sort((a,b) => new Date(a.date)-new Date(b.date));

  matchCache.set(liveMatches);
  return liveMatches;
}

// ── AUTO-RESOLVE ──────────────────────────────────────────────────────────────
function evaluatePick(market, fixture) {
  const home=fixture.teams.home.name, away=fixture.teams.away.name;
  const hg=fixture.goals.home??0, ag=fixture.goals.away??0, total=hg+ag;
  const htH=fixture.score?.halftime?.home??0, htA=fixture.score?.halftime?.away??0;
  if (!FINISH_STATUSES.includes(fixture.fixture.status.short)) return null;
  const m=market.toLowerCase();
  if(m===`${home.toLowerCase()} win`) return hg>ag?"correct":"wrong";
  if(m==="draw") return hg===ag?"correct":"wrong";
  if(m===`${away.toLowerCase()} win`) return ag>hg?"correct":"wrong";
  if(m.includes("or draw")&&m.includes(home.toLowerCase())) return hg>=ag?"correct":"wrong";
  if(m.includes("or draw")&&m.includes(away.toLowerCase())) return ag>=hg?"correct":"wrong";
  const under=m.match(/(?:under|0-) (\d+)/); if(under) return total<parseInt(under[1])?"correct":"wrong";
  const over=m.match(/(\d+)\+/); if(over) return total>=parseInt(over[1])?"correct":"wrong";
  const exact=m.match(/exactly (\d+)/); if(exact) return total===parseInt(exact[1])?"correct":"wrong";
  if(m==="no goals") return total===0?"correct":"wrong";
  if(m.startsWith("yes")&&m.includes("both")) return hg>0&&ag>0?"correct":"wrong";
  if(m.startsWith("no")&&m.includes("blank")) return hg===0||ag===0?"correct":"wrong";
  if(m.includes("leading")&&m.includes(home.toLowerCase())) return htH>htA?"correct":"wrong";
  if(m.includes("level at")) return htH===htA?"correct":"wrong";
  if(m.includes("leading")&&m.includes(away.toLowerCase())) return htA>htH?"correct":"wrong";
  if(m.includes("clean sheet")&&m.includes(home.toLowerCase())) return ag===0?"correct":"wrong";
  if(m.includes("clean sheet")&&m.includes(away.toLowerCase())) return hg===0?"correct":"wrong";
  const score=m.match(/^(\d+)-(\d+)$/); if(score) return parseInt(score[1])===hg&&parseInt(score[2])===ag?"correct":"wrong";
  if(m==="goals odd") return total%2!==0?"correct":"wrong";
  if(m==="goals even") return total%2===0?"correct":"wrong";
  return null;
}


async function resolveCombo(comboId) {
  const { data: allLegs } = await supabaseAdmin
    .from("picks").select("*").eq("combo_id", comboId);
  if (!allLegs?.length) return;

  // Wait until all legs resolved
  if (allLegs.some(p => p.result === "pending")) return;

  const correct = allLegs.filter(p => p.result === "correct").length;
  const total   = allLegs.length;

  if (correct === 0) return; // all wrong — no bonus

  // ── Combo brave bonus ─────────────────────────────────────────────────────
  // Guaranteed multiplier just for attempting a multi-pick combo
  const comboMultiplier = { 2: 1.1, 3: 1.2, 4: 1.3, 5: 1.4 }[total] || 1.0;

  // Rate: full combo = 100%, partial = (correct/total) × 50%
  const rate = correct === total ? 1.0 : (correct / total) * 0.5;

  const { data: profile } = await supabaseAdmin
    .from("profiles").select("*").eq("id", allLegs[0].user_id).single();
  if (!profile) return;

  // Base XP from correct legs only
  const baseXP = allLegs
    .filter(p => p.result === "correct")
    .reduce((sum, leg) => {
      const prob = leg.probability || Math.min(99, Math.max(1, Math.round(100.0 / (leg.odds || 2.0))));
      return sum + calcPointsWin(prob);
    }, 0);

  // Final XP = base × combo multiplier × rate
  const totalBonus = Math.round(baseXP * comboMultiplier * rate);

  // Distribute bonus across correct legs proportionally
  for (const leg of allLegs.filter(p => p.result === "correct")) {
    const prob     = leg.probability || Math.min(99, Math.max(1, Math.round(100.0 / (leg.odds || 2.0))));
    const legBase  = calcPointsWin(prob);
    const legBonus = Math.round(legBase * comboMultiplier * rate);
    await supabaseAdmin.from("picks")
      .update({ points_earned: legBonus }).eq("id", leg.id);
  }

  // Wrong legs get 0 XP (overrides negative from normal resolution)
  for (const leg of allLegs.filter(p => p.result === "wrong")) {
    await supabaseAdmin.from("picks")
      .update({ points_earned: 0 }).eq("id", leg.id);
  }

  // Add to profile — no streak update for partial combos
  const isFullCombo = correct === total;
  await supabaseAdmin.from("profiles").update({
    total_points:      (profile.total_points  || 0) + totalBonus,
    weekly_points:     (profile.weekly_points || 0) + totalBonus,
    // Only update streak on full combo win
    current_streak:    isFullCombo ? (profile.current_streak || 0) + 1 : profile.current_streak || 0,
    best_streak:       isFullCombo ? Math.max(profile.best_streak || 0, (profile.current_streak || 0) + 1) : profile.best_streak || 0,
  }).eq("id", allLegs[0].user_id);

  console.log(`🎯 Combo ${comboId}: ${correct}/${total} | ×${comboMultiplier} | rate ${Math.round(rate*100)}% | +${totalBonus} XP`);
}


async function resolvePlayerGoalPicks(fixtureId, pendingPicks, profileCache) {
    if (!pendingPicks.length) return 0;

    const { counts, firstScorer, lastScorer } = await fetchGoalEvents(fixtureId);
    const playerNames = Object.keys(counts);
    let resolved = 0;

    for (const pick of pendingPicks) {
        const market  = pick.market || "";
        const mLower  = market.toLowerCase();
        let result    = null;

        // Detect market type from the suffix we embed in PredictViewModel
        if (mLower.includes("(2+ goals)")) {
            const matched = fuzzyMatch(market, playerNames);
            const scored  = matched ? (counts[matched] ?? 0) : 0;
            result = scored >= 2 ? "correct" : "wrong";

        } else if (mLower.includes("(hat-trick)")) {
            const matched = fuzzyMatch(market, playerNames);
            const scored  = matched ? (counts[matched] ?? 0) : 0;
            result = scored >= 3 ? "correct" : "wrong";

        } else if (mLower.includes("(anytime)")) {
            const matched = fuzzyMatch(market, playerNames);
            result = matched ? "correct" : "wrong";

        } else if (mLower.includes("(1st goal)")) {
            const matched = fuzzyMatch(market, firstScorer ? [firstScorer] : []);
            result = matched ? "correct" : "wrong";

        } else if (mLower.includes("(last goal)")) {
            const matched = fuzzyMatch(market, lastScorer ? [lastScorer] : []);
            result = matched ? "correct" : "wrong";

        } else {
            continue; // not a player goal pick we can resolve
        }

        const prob    = pick.probability || Math.min(99, Math.max(1, Math.round(100.0 / (pick.odds || 2.0))));
        let profile   = profileCache[pick.user_id];
        if (!profile) {
            const { data } = await supabaseAdmin.from("profiles").select("*").eq("id", pick.user_id).single();
            profile = data;
            profileCache[pick.user_id] = profile;
        }
        if (!profile) continue;

        let fp = 0, ns = 0;
        if (result === "correct") {
            ns = (profile.current_streak || 0) + 1;
            fp = Math.round(calcPointsWin(prob) * getStreakMultiplier(ns) * getDailyBonus(profile.daily_streak));
        } else {
            fp = -calcPointsLoss(prob);
        }

        const du = updateDailyStreak(profile);
        await supabaseAdmin.from("picks").update({ result, points_earned: fp }).eq("id", pick.id);
        await supabaseAdmin.from("profiles").update({
            current_streak:    result === "correct" ? ns : 0,
            best_streak:       Math.max(profile.best_streak || 0, ns),
            total_points:      (profile.total_points  || 0) + fp,
            weekly_points:     (profile.weekly_points || 0) + fp,
            daily_streak:      du.daily_streak,
            best_daily_streak: du.best_daily_streak,
            last_pick_date:    du.last_pick_date,
        }).eq("id", pick.user_id);

        // Update cache so next leg of the same combo uses fresh profile data
        profileCache[pick.user_id] = {
            ...profile,
            current_streak: result === "correct" ? ns : 0,
            total_points:   (profile.total_points  || 0) + fp,
            weekly_points:  (profile.weekly_points || 0) + fp,
        };

        resolved++;
    }
    return resolved;
}


async function resolvePicksForMatch(fixture) {
    const { data: picks } = await supabaseAdmin
        .from("picks").select("*").eq("result", "pending")
        .ilike("match", `%${fixture.teams.home.name}%`);
    if (!picks?.length) return 0;

    let resolved = 0;
    const comboIdsToCheck = new Set();
    const profileCache    = {};   // avoid re-fetching same profile multiple times

    // ── Pass 1: standard market resolution ───────────────────────────────────
    for (const pick of picks) {
        if (!pick.match.toLowerCase().includes(fixture.teams.away.name.toLowerCase())) continue;
        const result = evaluatePick(pick.market, fixture);
        if (!result) continue;

        const prob = pick.probability || Math.min(99, Math.max(1, Math.round(100.0 / (pick.odds || 2.0))));
        const { data: profile } = await supabaseAdmin.from("profiles").select("*").eq("id", pick.user_id).single();
        if (!profile) continue;

        profileCache[pick.user_id] = profile;
        let ns = 0, fp = 0;
        if (result === "correct") {
            ns = (profile.current_streak || 0) + 1;
            fp = Math.round(calcPointsWin(prob) * getStreakMultiplier(ns) * getDailyBonus(profile.daily_streak));
        } else {
            fp = -calcPointsLoss(prob);
        }
        const du = updateDailyStreak(profile);
        await supabaseAdmin.from("picks").update({ result, points_earned: fp }).eq("id", pick.id);
        await supabaseAdmin.from("profiles").update({
            current_streak:    result === "correct" ? ns : 0,
            best_streak:       Math.max(profile.best_streak || 0, ns),
            total_points:      (profile.total_points  || 0) + fp,
            weekly_points:     (profile.weekly_points || 0) + fp,
            daily_streak:      du.daily_streak,
            best_daily_streak: du.best_daily_streak,
            last_pick_date:    du.last_pick_date,
        }).eq("id", pick.user_id);
        resolved++;
        if (pick.combo_id) comboIdsToCheck.add(pick.combo_id);
    }

    // ── Pass 2: player goalscorer resolution (needs events endpoint) ──────────
    const { data: stillPending } = await supabaseAdmin
        .from("picks").select("*").eq("result", "pending")
        .ilike("match", `%${fixture.teams.home.name}%`);

    const playerPicks = (stillPending || []).filter(p =>
        p.match.toLowerCase().includes(fixture.teams.away.name.toLowerCase()) &&
        /\((anytime|1st goal|last goal|2\+ goals|hat-trick)\)/i.test(p.market)
    );

    if (playerPicks.length > 0) {
        const playerResolved = await resolvePlayerGoalPicks(
            fixture.fixture.id, playerPicks, profileCache
        );
        resolved += playerResolved;
        playerPicks.forEach(p => { if (p.combo_id) comboIdsToCheck.add(p.combo_id); });
    }

    // ── Pass 3: combo partial credit ─────────────────────────────────────────
    for (const comboId of comboIdsToCheck) {
        await resolveCombo(comboId);
    }

    return resolved;
}
// ── ROUTES ────────────────────────────────────────────────────────────────────
app.get("/", (req,res) => res.send("Predkt API 🚀"));

// ✅ Debug route — check odds for any fixture, see raw player prop data
app.get("/api/odds-debug/:fixtureId", async(req,res)=>{
  const id = parseInt(req.params.fixtureId);
  if (!id) return res.status(400).json({ error: "Invalid ID" });
  const headers = { "x-apisports-key": process.env.API_FOOTBALL_KEY };
  const bookmakerIds = [2, 4, 7, 8, 1, 6];
  try {
    const results = await Promise.all(
      bookmakerIds.map(async bm => {
        const data = await fetch(`${API_BASE}/odds?fixture=${id}&bookmaker=${bm}`, {headers}).then(r=>r.json());
        const bets = data.response?.[0]?.bookmakers?.[0]?.bets || [];
        const playerBets = bets.filter(b =>
          [26,27,28,29,30,31,32].includes(b.id) || b.name?.includes("Goalscorer") || b.name?.includes("Player")
        );
        return {
          bookmaker: bm,
          totalMarkets: bets.length,
          playerMarkets: playerBets.length,
          playerSample: playerBets.slice(0,2).map(b => ({
            name: b.name,
            id:   b.id,
            players: b.values?.slice(0,5).map(v => v.value) || []
          }))
        };
      })
    );
    res.json({ fixtureId: id, bookmakers: results });
  } catch(err) { res.status(500).json({ error: err.message }); }
});

app.get("/api/debug", async(req,res)=>{
  if(!process.env.API_FOOTBALL_KEY) return res.json({error:"API_FOOTBALL_KEY missing"});
  try {
    const season  = currentSeason();
    const headers = {"x-apisports-key":process.env.API_FOOTBALL_KEY};
    const [test, status] = await Promise.all([
      fetch(`${API_BASE}/fixtures?league=39&season=${season}&from=${dateStr(0)}&to=${dateStr(7)}`,{headers}).then(r=>r.json()),
      fetch(`${API_BASE}/status`,{headers}).then(r=>r.json()),
    ]);
    res.json({
    season,
    plan:       status.response?.subscription?.plan ?? "?",
    requests:   `${status.response?.requests?.current ?? 0}/${status.response?.requests?.limit_day ?? 0}`,
    plFixtures: test.response?.length ?? 0,
    errors:     test.errors ?? null,
    cacheSize:  matchCache.data?.length ?? 0,
    cacheStale: matchCache.isStale(),
    cachedDays: matchCache.data ? [...new Set(matchCache.data.map(m => m.date.slice(0,10)))].sort() : [],
    // ✅ Show upcoming fixture IDs for odds-debug testing
    upcomingFixtures: (matchCache.data || [])
        .filter(m => !m.isLive && !m.isFinished)
        .slice(0, 10)
        .map(m => ({
            id:          m.fixtureId,
            match:       `${m.home} vs ${m.away}`,
            competition: m.competition,
            date:        m.date,
        })),
    leagues: TOP_LEAGUES,
});
  }catch(err){res.json({error:err.message});}
});

app.get("/api/matches", async(req,res)=>{
  try { res.json({liveMatches: await buildMatchList()}); }
  catch(err){ console.error("❌",err.message); res.status(500).json({error:err.message}); }
});

app.get("/api/odds/:fixtureId", async(req,res)=>{
  const id=parseInt(req.params.fixtureId);
  if(!id) return res.status(400).json({error:"Invalid ID"});
  const fixture=matchCache.data?.find(f=>f.fixtureId===id);
  if(fixture&&(fixture.isLive||fixture.isFinished)) return res.json({odds:null});
  // Clear odds cache for this fixture so we re-fetch with merged bookmakers
  oddsCache.delete(id);
  try{
    const odds=await fetchOddsForId(id);
    res.set("Cache-Control","public, max-age=3600");
    res.json({odds});
  }catch(err){res.status(500).json({error:err.message});}
});

app.get("/api/live", async(req,res)=>{
  try{
    const f=await apiFetch("/fixtures",{live:"all"});
    res.json({liveMatches:f.map(x=>mapFixture(x))});
  }catch(err){res.status(500).json({error:err.message});}
});

app.post("/api/refresh-cache", requireAdmin, async(req,res)=>{
  matchCache.invalidate(); oddsCache.clear();
  try{await buildMatchList(); res.json({ok:true});}
  catch(err){res.status(500).json({error:err.message});}
});

app.post("/api/auto-resolve", async(req,res)=>{
  try{
    const f=await apiFetch("/fixtures",{status:"FT",last:30});
    let t=0; for(const x of f){t+=await resolvePicksForMatch(x);}
    res.json({ok:true,resolved:t});
  }catch(err){res.status(500).json({error:err.message});}
});

app.post("/api/resolve", requireAdmin, async(req,res)=>{
  const{pickId,result}=req.body;
  const{data:pick}=await supabaseAdmin.from("picks").select("*").eq("id",pickId).single();
  const{data:profile}=await supabaseAdmin.from("profiles").select("*").eq("id",pick.user_id).single();
  const prob=pick.probability||Math.min(99,Math.max(1,Math.round(100.0/(pick.odds||2.0))));
  let ns=0,fp=0;
  if(result==="correct"){ns=(profile.current_streak||0)+1;fp=Math.round(calcPointsWin(prob)*getStreakMultiplier(ns)*getDailyBonus(profile.daily_streak));}
  else{fp=-calcPointsLoss(prob);}
  const du=updateDailyStreak(profile);
  await supabaseAdmin.from("picks").update({result,points_earned:fp}).eq("id",pickId);
  await supabaseAdmin.from("profiles").update({current_streak:result==="correct"?ns:0,best_streak:Math.max(profile.best_streak||0,ns),total_points:(profile.total_points||0)+fp,weekly_points:(profile.weekly_points||0)+fp,daily_streak:du.daily_streak,best_daily_streak:du.best_daily_streak,last_pick_date:du.last_pick_date}).eq("id",pick.user_id);
  res.json({ok:true});
});

app.post("/api/weekly-reset", requireAdmin, async(req,res)=>{
  try{await supabaseAdmin.rpc("reset_weekly_points"); res.json({ok:true});}
  catch(err){res.status(500).json({error:err.message});}
});

// ── CRONS ─────────────────────────────────────────────────────────────────────
cron.schedule("*/20 * * * *", async()=>{
  try{
    const f=await apiFetch("/fixtures",{status:"FT",last:20});
    let t=0; for(const x of f){t+=await resolvePicksForMatch(x);}
    if(t>0) console.log(`⏰ Resolved ${t}`);
  }catch(err){console.error("❌ Auto-resolve:",err.message);}
});

cron.schedule("0 */2 * * *", async()=>{
  matchCache.invalidate();
  try{await buildMatchList();}catch(err){console.error("❌ Cache:",err.message);}
});

cron.schedule("0 0 * * 1", async()=>{
  try{await supabaseAdmin.rpc("reset_weekly_points"); console.log("✅ Weekly reset");}
  catch(err){console.error("❌",err.message);}
});

// ── START ─────────────────────────────────────────────────────────────────────
const PORT=process.env.PORT||8080;
app.listen(PORT,"0.0.0.0",()=>{
  console.log(`✅ Predkt API on port ${PORT}`);
  setTimeout(()=>buildMatchList(), 3000);
})
