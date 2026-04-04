// Client-side API calls to API-Football
// CapacitorHttp (enabled in capacitor.config.json) patches fetch to use native HTTP, bypassing CORS
const BASE = "https://v3.football.api-sports.io";
const KEY  = process.env.NEXT_PUBLIC_API_FOOTBALL_KEY;

const HEADERS = {
  "x-rapidapi-key":  KEY,
  "x-rapidapi-host": "v3.football.api-sports.io",
};

// Top 20 leagues/cups — club competitions + major internationals
const LEAGUES = [
  { id: 2,   name: "UEFA Champions League" },
  { id: 3,   name: "UEFA Europa League" },
  { id: 848, name: "UEFA Conference League" },
  { id: 39,  name: "Premier League" },
  { id: 40,  name: "Championship" },
  { id: 45,  name: "FA Cup" },
  { id: 48,  name: "EFL Cup" },
  { id: 140, name: "La Liga" },
  { id: 143, name: "Copa del Rey" },
  { id: 78,  name: "Bundesliga" },
  { id: 81,  name: "DFB-Pokal" },
  { id: 135, name: "Serie A" },
  { id: 137, name: "Coppa Italia" },
  { id: 61,  name: "Ligue 1" },
  { id: 66,  name: "Coupe de France" },
  { id: 94,  name: "Primeira Liga" },
  { id: 88,  name: "Eredivisie" },
  { id: 71,  name: "Brasileirao" },
  { id: 253, name: "MLS" },
  { id: 1,   name: "World Cup" },
];

// International tournaments use the tournament year as season; clubs use start year of season
const INTERNATIONAL_IDS = new Set([1, 4, 5, 6, 9, 10]);

function getCurrentSeason() {
  const now = new Date();
  const y   = now.getFullYear();
  const m   = now.getMonth() + 1; // 1-12
  // Club seasons start in Aug/Sep; use next year's season from July onward
  return m >= 7 ? y : y - 1;
}

function getSeasonForLeague(id) {
  if (INTERNATIONAL_IDS.has(id)) {
    // Return the current or upcoming tournament year
    const y = new Date().getFullYear();
    return y;
  }
  return getCurrentSeason();
}

function formatKickoff(dateStr) {
  const d   = new Date(dateStr);
  const now = new Date();
  const tom = new Date(now); tom.setDate(now.getDate() + 1);
  const t   = d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", timeZone: "Europe/London" });
  const day = d.toLocaleDateString("en-GB", { weekday: "short", timeZone: "Europe/London" });
  const dt  = d.toLocaleDateString("en-GB", { day: "numeric", month: "short", timeZone: "Europe/London" });
  if (d.toDateString() === now.toDateString()) return `Today ${t}`;
  if (d.toDateString() === tom.toDateString()) return `Tomorrow ${t}`;
  return `${day} ${dt} ${t}`;
}

export async function fetchMatches() {
  if (!KEY) throw new Error("API key not configured");

  const from = new Date().toISOString().split("T")[0];
  const to   = new Date(Date.now() + 13 * 86400000).toISOString().split("T")[0];

  const responses = await Promise.allSettled(
    LEAGUES.map(({ id }) => {
      const season = getSeasonForLeague(id);
      return fetch(
        `${BASE}/fixtures?league=${id}&season=${season}&from=${from}&to=${to}&status=NS`,
        { headers: HEADERS }
      )
        .then(r => r.json())
        .then(data => data.response || [])
        .catch(() => []);
    })
  );

  const all = responses
    .filter(r => r.status === "fulfilled")
    .flatMap(r => r.value);

  all.sort((a, b) => new Date(a.fixture.date) - new Date(b.fixture.date));

  return all.map(f => ({
    id:          f.fixture.id,
    fixtureId:   f.fixture.id,
    home:        f.teams.home.name,
    away:        f.teams.away.name,
    homeCrest:   f.teams.home.logo || null,
    awayCrest:   f.teams.away.logo || null,
    time:        formatKickoff(f.fixture.date),
    competition: f.league?.name  || null,
    compCrest:   f.league?.logo  || null,
    venue:       f.fixture.venue?.name || null,
    rawDate:     f.fixture.date,
  }));
}

// ─── Risk label ───────────────────────────────────────────────────
function risk(odds) {
  if (!odds || isNaN(odds)) return { label: "—",         color: "#4a4958" };
  if (odds <= 1.3)          return { label: "Banker",    color: "#22c55e" };
  if (odds <= 1.7)          return { label: "Safe",      color: "#22c55e" };
  if (odds <= 2.5)          return { label: "Fair",      color: "#f59e0b" };
  if (odds <= 4.0)          return { label: "Risky",     color: "#f97316" };
  if (odds <= 8.0)          return { label: "Long shot", color: "#ef4444" };
  return                         { label: "Jackpot",    color: "#a855f7" };
}

// ─── Default markets (used when live odds not available) ──────────
function getDefaultMarkets(home, away) {
  const r = o => risk(o);
  return [
    { category: "Match result", options: [
      { label: (home||"Home")+" win", odds: null, key: "h2h:home", risk: r(null) },
      { label: "Draw",                odds: null, key: "h2h:draw", risk: r(null) },
      { label: (away||"Away")+" win", odds: null, key: "h2h:away", risk: r(null) },
    ]},
    { category: "Double chance", options: [
      { label: "Home or draw", odds: 1.25, key: "dc:home_draw", risk: r(1.25) },
      { label: "Home or away", odds: 1.20, key: "dc:home_away", risk: r(1.20) },
      { label: "Draw or away", odds: 1.55, key: "dc:draw_away", risk: r(1.55) },
    ]},
    { category: "Goals", options: [
      { label: "Over 0.5 goals",  odds: 1.12, key: "totals:over_0.5",  risk: r(1.12) },
      { label: "Over 1.5 goals",  odds: 1.45, key: "totals:over_1.5",  risk: r(1.45) },
      { label: "Over 2.5 goals",  odds: 1.95, key: "totals:over_2.5",  risk: r(1.95) },
      { label: "Over 3.5 goals",  odds: 2.90, key: "totals:over_3.5",  risk: r(2.90) },
      { label: "Over 4.5 goals",  odds: 4.50, key: "totals:over_4.5",  risk: r(4.50) },
      { label: "Under 1.5 goals", odds: 2.80, key: "totals:under_1.5", risk: r(2.80) },
      { label: "Under 2.5 goals", odds: 1.95, key: "totals:under_2.5", risk: r(1.95) },
      { label: "Under 3.5 goals", odds: 1.40, key: "totals:under_3.5", risk: r(1.40) },
    ]},
    { category: "Both teams to score", options: [
      { label: "Both score", odds: 1.85, key: "btts:yes", risk: r(1.85) },
      { label: "Not both",   odds: 2.00, key: "btts:no",  risk: r(2.00) },
    ]},
    { category: "Half time result", options: [
      { label: "Home win HT", odds: 2.80, key: "ht:home", risk: r(2.80) },
      { label: "Draw HT",     odds: 2.20, key: "ht:draw", risk: r(2.20) },
      { label: "Away win HT", odds: 4.20, key: "ht:away", risk: r(4.20) },
    ]},
    { category: "First half goals", options: [
      { label: "Over 0.5 goals 1H",  odds: 1.65, key: "fhg:over_0.5",  risk: r(1.65) },
      { label: "Over 1.5 goals 1H",  odds: 2.60, key: "fhg:over_1.5",  risk: r(2.60) },
      { label: "Over 2.5 goals 1H",  odds: 5.50, key: "fhg:over_2.5",  risk: r(5.50) },
      { label: "Under 0.5 goals 1H", odds: 2.20, key: "fhg:under_0.5", risk: r(2.20) },
      { label: "Under 1.5 goals 1H", odds: 1.50, key: "fhg:under_1.5", risk: r(1.50) },
    ]},
    { category: "BTTS first half", options: [
      { label: "Both score 1H", odds: 3.80, key: "bttsht:yes", risk: r(3.80) },
      { label: "Not both 1H",   odds: 1.25, key: "bttsht:no",  risk: r(1.25) },
    ]},
    { category: "Win to nil", options: [
      { label: (home||"Home")+" to nil", odds: 3.20, key: "wtn:home", risk: r(3.20) },
      { label: (away||"Away")+" to nil", odds: 4.50, key: "wtn:away", risk: r(4.50) },
    ]},
    { category: "First to score", options: [
      { label: (home||"Home")+" first", odds: 2.10, key: "tsf:home", risk: r(2.10) },
      { label: (away||"Away")+" first", odds: 2.80, key: "tsf:away", risk: r(2.80) },
      { label: "No goal",               odds: 10.0, key: "tsf:no",   risk: r(10.0)  },
    ]},
    { category: "Exact goals", options: [
      { label: "Exactly 0 goals", odds: 10.0, key: "exact:0", risk: r(10.0) },
      { label: "Exactly 1 goal",  odds: 5.50, key: "exact:1", risk: r(5.50) },
      { label: "Exactly 2 goals", odds: 3.40, key: "exact:2", risk: r(3.40) },
      { label: "Exactly 3 goals", odds: 4.20, key: "exact:3", risk: r(4.20) },
      { label: "Exactly 4 goals", odds: 7.50, key: "exact:4", risk: r(7.50) },
    ]},
    { category: "Asian handicap", options: [
      { label: (home||"Home")+" -0.5", odds: 1.95, key: "ah:home_-0.5", risk: r(1.95) },
      { label: (home||"Home")+" -1.5", odds: 2.80, key: "ah:home_-1.5", risk: r(2.80) },
      { label: (away||"Away")+" -0.5", odds: 1.95, key: "ah:away_-0.5", risk: r(1.95) },
      { label: (away||"Away")+" -1.5", odds: 2.80, key: "ah:away_-1.5", risk: r(2.80) },
    ]},
    { category: "Corners", options: [
      { label: "Over 8.5 corners",  odds: 1.90, key: "corners_over_8.5",  risk: r(1.90) },
      { label: "Over 9.5 corners",  odds: 2.40, key: "corners_over_9.5",  risk: r(2.40) },
      { label: "Over 10.5 corners", odds: 3.20, key: "corners_over_10.5", risk: r(3.20) },
      { label: "Under 8.5 corners", odds: 2.10, key: "corners_under_8.5", risk: r(2.10) },
      { label: "Under 9.5 corners", odds: 1.65, key: "corners_under_9.5", risk: r(1.65) },
    ]},
    { category: "Cards", options: [
      { label: "Over 1.5 cards",  odds: 1.55, key: "cards_over_1.5",  risk: r(1.55) },
      { label: "Over 2.5 cards",  odds: 2.10, key: "cards_over_2.5",  risk: r(2.10) },
      { label: "Over 3.5 cards",  odds: 3.40, key: "cards_over_3.5",  risk: r(3.40) },
      { label: "Over 4.5 cards",  odds: 6.00, key: "cards_over_4.5",  risk: r(6.00) },
      { label: "Under 2.5 cards", odds: 1.80, key: "cards_under_2.5", risk: r(1.80) },
      { label: "Under 3.5 cards", odds: 1.30, key: "cards_under_3.5", risk: r(1.30) },
    ]},
    { category: "HT/FT result", options: [
      { label: "Home/Home", odds: 3.50,  key: "htft:home-home", risk: r(3.50)  },
      { label: "Home/Draw", odds: 12.00, key: "htft:home-draw", risk: r(12.00) },
      { label: "Home/Away", odds: 18.00, key: "htft:home-away", risk: r(18.00) },
      { label: "Draw/Home", odds: 4.00,  key: "htft:draw-home", risk: r(4.00)  },
      { label: "Draw/Draw", odds: 3.80,  key: "htft:draw-draw", risk: r(3.80)  },
      { label: "Draw/Away", odds: 5.50,  key: "htft:draw-away", risk: r(5.50)  },
      { label: "Away/Home", odds: 20.00, key: "htft:away-home", risk: r(20.00) },
      { label: "Away/Draw", odds: 14.00, key: "htft:away-draw", risk: r(14.00) },
      { label: "Away/Away", odds: 4.50,  key: "htft:away-away", risk: r(4.50)  },
    ]},
    { category: "Correct score", options: [
      { label: "1-0",  odds: 7.00,  key: "cs:1-0",  risk: r(7.00)  },
      { label: "2-0",  odds: 9.00,  key: "cs:2-0",  risk: r(9.00)  },
      { label: "2-1",  odds: 9.50,  key: "cs:2-1",  risk: r(9.50)  },
      { label: "3-0",  odds: 13.00, key: "cs:3-0",  risk: r(13.00) },
      { label: "3-1",  odds: 15.00, key: "cs:3-1",  risk: r(15.00) },
      { label: "3-2",  odds: 22.00, key: "cs:3-2",  risk: r(22.00) },
      { label: "1-1",  odds: 6.50,  key: "cs:1-1",  risk: r(6.50)  },
      { label: "2-2",  odds: 12.00, key: "cs:2-2",  risk: r(12.00) },
      { label: "3-3",  odds: 40.00, key: "cs:3-3",  risk: r(40.00) },
      { label: "0-0",  odds: 10.00, key: "cs:0-0",  risk: r(10.00) },
      { label: "0-1",  odds: 8.00,  key: "cs:0-1",  risk: r(8.00)  },
      { label: "0-2",  odds: 10.50, key: "cs:0-2",  risk: r(10.50) },
      { label: "1-2",  odds: 10.50, key: "cs:1-2",  risk: r(10.50) },
      { label: "0-3",  odds: 17.00, key: "cs:0-3",  risk: r(17.00) },
      { label: "1-3",  odds: 20.00, key: "cs:1-3",  risk: r(20.00) },
      { label: "2-3",  odds: 25.00, key: "cs:2-3",  risk: r(25.00) },
    ]},
  ];
}

// ─── Build markets from live bookmaker data ───────────────────────
function buildMarkets(bm, home, away) {
  const bets    = bm.bets || [];
  const markets = [];
  const find    = name => bets.find(b => b.name.toLowerCase().includes(name.toLowerCase()));
  const opt     = (label, odds, key) => ({ label, odds: parseFloat(odds), key, risk: risk(parseFloat(odds)) });

  // 1. Match result
  const mr = find("Match Winner") || find("1X2");
  if (mr) markets.push({ category: "Match result", options: mr.values.map(v => opt(
    v.value === "Home" ? (home||"Home")+" win" : v.value === "Away" ? (away||"Away")+" win" : "Draw",
    v.odd, "h2h:"+v.value.toLowerCase()
  ))});

  // 2. Double chance
  const dc = find("Double Chance");
  if (dc) markets.push({ category: "Double chance", options: dc.values.map(v => opt(
    v.value === "Home/Draw" ? "Home or draw" : v.value === "Home/Away" ? "Home or away" : "Draw or away",
    v.odd, "dc:"+v.value.toLowerCase().replace("/","_")
  ))});

  // 3. Goals over/under
  const goals = find("Goals Over/Under");
  if (goals) {
    const sorted = [...goals.values].sort((a,b) => parseFloat(a.value.split(" ")[1]) - parseFloat(b.value.split(" ")[1]));
    markets.push({ category: "Goals", options: sorted.map(v => opt(v.value+" goals", v.odd, "totals:"+v.value.toLowerCase().replace(" ","_"))) });
  }

  // 4. Both teams to score
  const btts = find("Both Teams Score") || find("BTTS");
  if (btts) markets.push({ category: "Both teams to score", options: btts.values.map(v => opt(
    v.value === "Yes" ? "Both score" : "Not both", v.odd, "btts:"+v.value.toLowerCase()
  ))});

  // 5. Half time result
  const ht = find("Halftime Result") || find("First Half Winner");
  if (ht) markets.push({ category: "Half time result", options: ht.values.map(v => opt(
    v.value === "Home" ? "Home win HT" : v.value === "Away" ? "Away win HT" : "Draw HT",
    v.odd, "ht:"+v.value.toLowerCase()
  ))});

  // 6. HT/FT double result
  const htft = find("HT/FT Double") || find("Half Time/Full Time");
  if (htft) markets.push({ category: "HT/FT result", options: htft.values.slice(0,9).map(v => opt(
    v.value, v.odd, "htft:"+v.value.toLowerCase().replace("/","-").replace(" ","_")
  ))});

  // 7. First half goals
  const fhg = find("First Half Goals") || find("Goals First Half");
  if (fhg) {
    const sorted = [...fhg.values].sort((a,b) => parseFloat(a.value.split(" ")[1]) - parseFloat(b.value.split(" ")[1]));
    markets.push({ category: "First half goals", options: sorted.map(v => opt(
      v.value+" goals 1H", v.odd, "fhg:"+v.value.toLowerCase().replace(" ","_")
    ))});
  }

  // 8. BTTS first half
  const bttsHT = find("Both Teams To Score First Half") || find("BTTS First Half");
  if (bttsHT) markets.push({ category: "BTTS first half", options: bttsHT.values.map(v => opt(
    v.value === "Yes" ? "Both score 1H" : "Not both 1H", v.odd, "bttsht:"+v.value.toLowerCase()
  ))});

  // 9. Win to nil
  const wtn = find("Win To Nil") || find("Clean Sheet");
  if (wtn) markets.push({ category: "Win to nil", options: wtn.values.map(v => opt(
    (v.value === "Home" ? (home||"Home") : (away||"Away"))+" to nil", v.odd, "wtn:"+v.value.toLowerCase()
  ))});

  // 10. First to score
  const tsf = find("Team To Score First");
  if (tsf) markets.push({ category: "First to score", options: tsf.values.map(v => opt(
    v.value === "Home" ? (home||"Home")+" first" : v.value === "Away" ? (away||"Away")+" first" : "No goal",
    v.odd, "tsf:"+v.value.toLowerCase()
  ))});

  // 11. Exact goals
  const eg = find("Exact Goals Number");
  if (eg) {
    const sorted = [...eg.values].sort((a,b) => parseInt(a.value) - parseInt(b.value));
    markets.push({ category: "Exact goals", options: sorted.map(v => opt("Exactly "+v.value+" goals", v.odd, "exact:"+v.value)) });
  }

  // 12. Asian handicap
  const ah = find("Asian Handicap");
  if (ah) {
    const clean = ah.values.filter(v => ["Home -0.5","Home -1.5","Away -0.5","Away -1.5","Home +0.5","Away +0.5"].includes(v.value));
    if (clean.length) markets.push({ category: "Asian handicap", options: clean.map(v => opt(
      (v.value.includes("Home") ? (home||"Home") : (away||"Away"))+" "+v.value.split(" ")[1],
      v.odd, "ah:"+v.value.toLowerCase().replace(" ","_")
    ))});
  }

  // 13. Corners
  const corners = find("Corner Kicks Over/Under") || find("Total Corners");
  if (corners) {
    const sorted = [...corners.values].sort((a,b) => parseFloat(a.value.split(" ")[1]) - parseFloat(b.value.split(" ")[1]));
    markets.push({ category: "Corners", options: sorted.map(v => opt(
      (v.value.includes("Over") ? "Over " : "Under ")+v.value.split(" ")[1]+" corners",
      v.odd, "corners_"+v.value.toLowerCase().replace(" ","_")
    ))});
  }

  // 14. Team corners
  const teamCorners = find("Team Corners");
  if (teamCorners) markets.push({ category: "Team corners", options: teamCorners.values.map(v => opt(
    v.value, v.odd, "tcorners:"+v.value.toLowerCase().replace(" ","_")
  ))});

  // 15. Cards
  const cards = find("Card Over/Under") || find("Total Bookings");
  if (cards) {
    const sorted = [...cards.values].sort((a,b) => parseFloat(a.value.split(" ")[1]) - parseFloat(b.value.split(" ")[1]));
    markets.push({ category: "Cards", options: sorted.map(v => opt(
      (v.value.includes("Over") ? "Over " : "Under ")+v.value.split(" ")[1]+" cards",
      v.odd, "cards_"+v.value.toLowerCase().replace(" ","_")
    ))});
  }

  // 16. Correct score
  const cs = find("Correct Score");
  if (cs) {
    const sorted = [...cs.values].sort((a,b) => parseFloat(a.odd) - parseFloat(b.odd));
    markets.push({ category: "Correct score", options: sorted.slice(0,16).map(v => opt(v.value, v.odd, "cs:"+v.value.replace(":","-"))) });
  }

  // 17. Anytime goalscorer
  const ags = find("Anytime Scorer") || find("Anytime Goalscorer");
  if (ags) {
    const sorted = [...ags.values].sort((a,b) => parseFloat(a.odd) - parseFloat(b.odd));
    markets.push({ category: "Anytime goalscorer", options: sorted.slice(0,16).map(v => opt(v.value, v.odd, "ags:"+v.value.toLowerCase().replace(/ /g,"_"))) });
  }

  // 18. First goalscorer
  const fgs = find("First Goalscorer");
  if (fgs) {
    const sorted = [...fgs.values].sort((a,b) => parseFloat(a.odd) - parseFloat(b.odd));
    markets.push({ category: "First goalscorer", options: sorted.slice(0,16).map(v => opt(v.value, v.odd, "fgs:"+v.value.toLowerCase().replace(/ /g,"_"))) });
  }

  // 19. Last goalscorer
  const lgs = find("Last Goalscorer");
  if (lgs) {
    const sorted = [...lgs.values].sort((a,b) => parseFloat(a.odd) - parseFloat(b.odd));
    markets.push({ category: "Last goalscorer", options: sorted.slice(0,16).map(v => opt(v.value, v.odd, "lgs:"+v.value.toLowerCase().replace(/ /g,"_"))) });
  }

  // 20. Brace scorer (2+ goals)
  const brace = find("Player To Score 2+") || find("Brace Scorer") || find("Score 2 Or More");
  if (brace) {
    const sorted = [...brace.values].sort((a,b) => parseFloat(a.odd) - parseFloat(b.odd));
    markets.push({ category: "Brace scorer (2+ goals)", options: sorted.slice(0,12).map(v => opt(v.value, v.odd, "brace:"+v.value.toLowerCase().replace(/ /g,"_"))) });
  }

  // 21. Hat-trick scorer
  const hattrick = find("Hat-Trick") || find("Hat Trick Scorer") || find("Player To Score Hat Trick");
  if (hattrick) {
    const sorted = [...hattrick.values].sort((a,b) => parseFloat(a.odd) - parseFloat(b.odd));
    markets.push({ category: "Hat-trick scorer", options: sorted.slice(0,10).map(v => opt(v.value, v.odd, "hattrick:"+v.value.toLowerCase().replace(/ /g,"_"))) });
  }

  // 22. Player to be booked (yellow card)
  const booked = find("Player To Be Carded") || find("Player To Receive A Card") || find("Anytime Bookie") || find("To Be Booked");
  if (booked) {
    const sorted = [...booked.values].sort((a,b) => parseFloat(a.odd) - parseFloat(b.odd));
    markets.push({ category: "Player to be booked", options: sorted.slice(0,16).map(v => opt(v.value, v.odd, "booked:"+v.value.toLowerCase().replace(/ /g,"_"))) });
  }

  // 23. Player to be sent off (red card)
  const redcard = find("Player To Be Sent Off") || find("Player Red Card") || find("Sent Off");
  if (redcard) {
    const sorted = [...redcard.values].sort((a,b) => parseFloat(a.odd) - parseFloat(b.odd));
    markets.push({ category: "Player to be sent off", options: sorted.slice(0,12).map(v => opt(v.value, v.odd, "redcard:"+v.value.toLowerCase().replace(/ /g,"_"))) });
  }

  // 24. Player to be fouled
  const fouled = find("Player To Be Fouled") || find("Player Fouled") || find("Most Fouled Player");
  if (fouled) {
    const sorted = [...fouled.values].sort((a,b) => parseFloat(a.odd) - parseFloat(b.odd));
    markets.push({ category: "Player to be fouled", options: sorted.slice(0,12).map(v => opt(v.value, v.odd, "fouled:"+v.value.toLowerCase().replace(/ /g,"_"))) });
  }

  // 25. Player to assist
  const assist = find("Player To Provide An Assist") || find("Anytime Assist") || find("Player Assist");
  if (assist) {
    const sorted = [...assist.values].sort((a,b) => parseFloat(a.odd) - parseFloat(b.odd));
    markets.push({ category: "Player to assist", options: sorted.slice(0,16).map(v => opt(v.value, v.odd, "assist:"+v.value.toLowerCase().replace(/ /g,"_"))) });
  }

  // 26. Player to score or assist
  const scoreAssist = find("Player To Score Or Assist") || find("Score Or Assist");
  if (scoreAssist) {
    const sorted = [...scoreAssist.values].sort((a,b) => parseFloat(a.odd) - parseFloat(b.odd));
    markets.push({ category: "Score or assist", options: sorted.slice(0,16).map(v => opt(v.value, v.odd, "scoreassist:"+v.value.toLowerCase().replace(/ /g,"_"))) });
  }

  // 27. Player shots on target
  const shots = find("Player Shots On Target") || find("Player To Have A Shot On Target");
  if (shots) {
    const sorted = [...shots.values].sort((a,b) => parseFloat(a.odd) - parseFloat(b.odd));
    markets.push({ category: "Player shots on target", options: sorted.slice(0,12).map(v => opt(v.value, v.odd, "shots:"+v.value.toLowerCase().replace(/ /g,"_"))) });
  }

  // 28. Player total shots
  const totalshots = find("Player Total Shots") || find("Player Shots");
  if (totalshots) {
    const sorted = [...totalshots.values].sort((a,b) => parseFloat(a.odd) - parseFloat(b.odd));
    markets.push({ category: "Player total shots", options: sorted.slice(0,12).map(v => opt(v.value, v.odd, "totalshots:"+v.value.toLowerCase().replace(/ /g,"_"))) });
  }

  // Fill missing categories with defaults
  const defaults = getDefaultMarkets(home, away);
  defaults.forEach(dm => { if (!markets.find(m => m.category === dm.category)) markets.push(dm); });

  return markets;
}

export async function fetchOdds(fixtureId, matchHome, matchAway) {
  if (!KEY) return { markets: getDefaultMarkets(matchHome, matchAway), live: false };
  if (!fixtureId) return { markets: getDefaultMarkets(matchHome, matchAway), live: false };

  try {
    const res      = await fetch(`${BASE}/odds?fixture=${fixtureId}`, { headers: HEADERS });
    const oddsData = await res.json();
    const allBMs   = oddsData.response?.[0]?.bookmakers || [];
    const bm       = allBMs.find(b => b.id === 1) || allBMs.find(b => b.id === 2) || allBMs[0];
    if (!bm) return { markets: getDefaultMarkets(matchHome, matchAway), live: false };
    return { markets: buildMarkets(bm, matchHome, matchAway), live: true };
  } catch {
    return { markets: getDefaultMarkets(matchHome, matchAway), live: false };
  }
}
