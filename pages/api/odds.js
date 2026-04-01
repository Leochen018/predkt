export default async function handler(req, res) {
  const API_KEY = process.env.ODDS_API_KEY;
  const { matchHome, matchAway } = req.query;

  if (!matchHome || !matchAway) {
    return res.status(400).json({ error: "Missing match teams" });
  }

  // Try multiple sport keys to find the match
  const sportKeys = [
    "soccer_epl",
    "soccer_england_championship",
    "soccer_uefa_champs_league",
    "soccer_uefa_europa_league",
    "soccer_spain_la_liga",
    "soccer_italy_serie_a",
    "soccer_germany_bundesliga",
    "soccer_france_ligue_one",
    "soccer_brazil_campeonato",
    "soccer_argentina_primera_division",
  ];

  try {
    let game = null;

    for (const sport of sportKeys) {
      const response = await fetch(
        `https://api.the-odds-api.com/v4/sports/${sport}/odds/?apiKey=${API_KEY}&regions=uk&markets=h2h,totals&oddsFormat=decimal`
      );
      if (!response.ok) continue;
      const games = await response.json();
      if (!Array.isArray(games)) continue;

      game = games.find(g =>
        g.home_team.toLowerCase().includes(matchHome.toLowerCase()) ||
        g.away_team.toLowerCase().includes(matchAway.toLowerCase()) ||
        matchHome.toLowerCase().includes(g.home_team.toLowerCase()) ||
        matchAway.toLowerCase().includes(g.away_team.toLowerCase())
      );

      if (game) break;
    }

    if (!game) {
      return res.status(200).json({ markets: getDefaultMarkets(matchHome, matchAway), live: false });
    }

    res.status(200).json({ markets: buildMarkets(game, matchHome, matchAway), live: true });

  } catch (error) {
    res.status(500).json({ error: "Server error: " + error.message });
  }
}

function buildMarkets(game, matchHome, matchAway) {
  const oddsMap = {};

  game.bookmakers.forEach(bm => {
    bm.markets.forEach(market => {
      market.outcomes.forEach(outcome => {
        const key = `${market.key}:${outcome.name}`;
        if (!oddsMap[key]) oddsMap[key] = { prices: [], name: outcome.name, market: market.key };
        oddsMap[key].prices.push(outcome.price);
      });
    });
  });

  const averaged = Object.entries(oddsMap).map(([key, val]) => ({
    key,
    marketKey: val.market,
    name:      val.name,
    odds:      parseFloat((val.prices.reduce((a, b) => a + b, 0) / val.prices.length).toFixed(2)),
  }));

  const markets = [];

  // Match result
  const h2h = averaged.filter(m => m.marketKey === "h2h");
  if (h2h.length) {
    markets.push({
      category: "Match result",
      options: h2h.map(m => {
        const odds = m.odds;
        const risk = getRiskLabel(odds);
        return {
          label:   m.name === "Draw" ? "Draw" : m.name + " win",
          odds,
          key:     m.key,
          risk,
        };
      }),
    });
  }

  // Goals — totals from API
  const totals = averaged.filter(m => m.marketKey === "totals");
  if (totals.length) {
    const sorted = [...totals].sort((a, b) => {
      const aNum = parseFloat(a.name.split(" ")[1]) || 0;
      const bNum = parseFloat(b.name.split(" ")[1]) || 0;
      return aNum - bNum;
    });
    markets.push({
      category: "Goals",
      options: sorted.map(m => ({
        label: m.name,
        odds:  m.odds,
        key:   m.key,
        risk:  getRiskLabel(m.odds),
      })),
    });
  }

  // Append fixed markets
  markets.push(...getFixedMarkets());
  return markets;
}

function getDefaultMarkets(matchHome, matchAway) {
  return [
    {
      category: "Match result",
      options: [
        { label: matchHome + " win", odds: null, key: "h2h:home", risk: getRiskLabel(null) },
        { label: "Draw",             odds: null, key: "h2h:draw", risk: getRiskLabel(null) },
        { label: matchAway + " win", odds: null, key: "h2h:away", risk: getRiskLabel(null) },
      ],
    },
    {
      category: "Goals",
      options: [
        { label: "Over 0.5 goals",  odds: null, key: "totals:over_0.5",  risk: getRiskLabel(null) },
        { label: "Over 1.5 goals",  odds: null, key: "totals:over_1.5",  risk: getRiskLabel(null) },
        { label: "Over 2.5 goals",  odds: null, key: "totals:over_2.5",  risk: getRiskLabel(null) },
        { label: "Over 3.5 goals",  odds: null, key: "totals:over_3.5",  risk: getRiskLabel(null) },
        { label: "Under 1.5 goals", odds: null, key: "totals:under_1.5", risk: getRiskLabel(null) },
        { label: "Under 2.5 goals", odds: null, key: "totals:under_2.5", risk: getRiskLabel(null) },
        { label: "Under 3.5 goals", odds: null, key: "totals:under_3.5", risk: getRiskLabel(null) },
      ],
    },
    ...getFixedMarkets(),
  ];
}

function getFixedMarkets() {
  return [
    {
      category: "Both teams to score",
      options: [
        { label: "Both score", odds: 1.85, key: "btts:yes", risk: getRiskLabel(1.85) },
        { label: "Not both",   odds: 2.00, key: "btts:no",  risk: getRiskLabel(2.00) },
      ],
    },
    {
      category: "Half time result",
      options: [
        { label: "Home win HT",  odds: 2.80, key: "ht:home", risk: getRiskLabel(2.80) },
        { label: "Draw HT",      odds: 2.20, key: "ht:draw", risk: getRiskLabel(2.20) },
        { label: "Away win HT",  odds: 4.20, key: "ht:away", risk: getRiskLabel(4.20) },
      ],
    },
    {
      category: "Double chance",
      options: [
        { label: "Home or draw",  odds: 1.30, key: "dc:home_draw", risk: getRiskLabel(1.30) },
        { label: "Home or away",  odds: 1.25, key: "dc:home_away", risk: getRiskLabel(1.25) },
        { label: "Draw or away",  odds: 1.60, key: "dc:draw_away", risk: getRiskLabel(1.60) },
      ],
    },
    {
      category: "Correct score",
      options: [
        { label: "1-0",  odds: 7.00,  key: "cs:1-0",  risk: getRiskLabel(7.00)  },
        { label: "2-0",  odds: 9.00,  key: "cs:2-0",  risk: getRiskLabel(9.00)  },
        { label: "2-1",  odds: 9.50,  key: "cs:2-1",  risk: getRiskLabel(9.50)  },
        { label: "1-1",  odds: 6.50,  key: "cs:1-1",  risk: getRiskLabel(6.50)  },
        { label: "0-0",  odds: 10.00, key: "cs:0-0",  risk: getRiskLabel(10.00) },
        { label: "0-1",  odds: 8.00,  key: "cs:0-1",  risk: getRiskLabel(8.00)  },
        { label: "0-2",  odds: 11.00, key: "cs:0-2",  risk: getRiskLabel(11.00) },
        { label: "1-2",  odds: 10.50, key: "cs:1-2",  risk: getRiskLabel(10.50) },
        { label: "3-0",  odds: 14.00, key: "cs:3-0",  risk: getRiskLabel(14.00) },
        { label: "3-1",  odds: 16.00, key: "cs:3-1",  risk: getRiskLabel(16.00) },
      ],
    },
    {
      category: "Corners",
      options: [
        { label: "Over 8.5 corners",  odds: 1.90, key: "corners_over_8.5",  risk: getRiskLabel(1.90) },
        { label: "Over 9.5 corners",  odds: 2.40, key: "corners_over_9.5",  risk: getRiskLabel(2.40) },
        { label: "Over 10.5 corners", odds: 3.20, key: "corners_over_10.5", risk: getRiskLabel(3.20) },
        { label: "Under 9.5 corners", odds: 2.10, key: "corners_under_9.5", risk: getRiskLabel(2.10) },
      ],
    },
    {
      category: "Cards",
      options: [
        { label: "Over 1.5 cards",  odds: 1.65, key: "cards_over_1.5",  risk: getRiskLabel(1.65) },
        { label: "Over 2.5 cards",  odds: 2.20, key: "cards_over_2.5",  risk: getRiskLabel(2.20) },
        { label: "Over 3.5 cards",  odds: 3.50, key: "cards_over_3.5",  risk: getRiskLabel(3.50) },
        { label: "Under 2.5 cards", odds: 2.00, key: "cards_under_2.5", risk: getRiskLabel(2.00) },
      ],
    },
  ];
}

function getRiskLabel(odds) {
  if (!odds) return { label: "—", color: "#4a4958" };
  if (odds <= 1.4)  return { label: "Low risk",    color: "#22c55e" };
  if (odds <= 1.9)  return { label: "Moderate",    color: "#22c55e" };
  if (odds <= 2.8)  return { label: "Medium risk", color: "#f59e0b" };
  if (odds <= 4.5)  return { label: "High risk",   color: "#f97316" };
  return               { label: "Extreme",      color: "#ef4444" };
}