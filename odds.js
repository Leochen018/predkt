export default async function handler(req, res) {
  const API_KEY   = process.env.ODDS_API_KEY;
  const { matchHome, matchAway } = req.query;

  if (!matchHome || !matchAway) {
    return res.status(400).json({ error: "Missing match teams" });
  }

  try {
    // Fetch odds for UK soccer (Premier League + other UK comps)
    const response = await fetch(
      `https://api.the-odds-api.com/v4/sports/soccer_epl/odds/?apiKey=${API_KEY}&regions=uk&markets=h2h,totals,btts,asian_handicap&oddsFormat=decimal`,
    );

    if (!response.ok) {
      const err = await response.json();
      return res.status(response.status).json({ error: err.message || "Failed to fetch odds" });
    }

    const games = await response.json();

    // Find the matching game
    const game = games.find(g =>
      g.home_team.toLowerCase().includes(matchHome.toLowerCase()) ||
      g.away_team.toLowerCase().includes(matchAway.toLowerCase()) ||
      matchHome.toLowerCase().includes(g.home_team.toLowerCase()) ||
      matchAway.toLowerCase().includes(g.away_team.toLowerCase())
    );

    if (!game) {
      // No odds found — return sensible default markets without odds
      return res.status(200).json({ markets: getDefaultMarkets() });
    }

    // Build market list from bookmaker data
    const markets = buildMarkets(game);
    res.status(200).json({ markets });

  } catch (error) {
    res.status(500).json({ error: "Server error: " + error.message });
  }
}

function buildMarkets(game) {
  const markets = [];

  // Gather all bookmakers and average their odds
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

  // Average the odds across bookmakers
  const averaged = Object.entries(oddsMap).map(([key, val]) => ({
    key,
    marketKey: val.market,
    name: val.name,
    odds: (val.prices.reduce((a, b) => a + b, 0) / val.prices.length).toFixed(2),
  }));

  // Group into categories
  const h2h         = averaged.filter(m => m.marketKey === "h2h");
  const totals      = averaged.filter(m => m.marketKey === "totals");
  const btts        = averaged.filter(m => m.marketKey === "btts");
  const handicap    = averaged.filter(m => m.marketKey === "asian_handicap");

  // Match result
  if (h2h.length) {
    markets.push({
      category: "Match result",
      options: h2h.map(m => ({
        label: formatOutcomeName(m.name, game.home_team, game.away_team),
        odds:  parseFloat(m.odds),
        key:   m.key,
      })),
    });
  }

  // Goals over/under
  if (totals.length) {
    const sorted = totals.sort((a, b) => {
      const aNum = parseFloat(a.name.split(" ")[1]) || 0;
      const bNum = parseFloat(b.name.split(" ")[1]) || 0;
      return aNum - bNum;
    });
    markets.push({
      category: "Goals",
      options: sorted.map(m => ({
        label: m.name,
        odds:  parseFloat(m.odds),
        key:   m.key,
      })),
    });
  }

  // Both teams to score
  if (btts.length) {
    markets.push({
      category: "Both teams to score",
      options: btts.map(m => ({
        label: m.name === "Yes" ? "Both score" : "Not both",
        odds:  parseFloat(m.odds),
        key:   m.key,
      })),
    });
  }

  // Handicap
  if (handicap.length) {
    markets.push({
      category: "Handicap",
      options: handicap.slice(0, 4).map(m => ({
        label: m.name,
        odds:  parseFloat(m.odds),
        key:   m.key,
      })),
    });
  }

  // Always add cards + corners as manual markets (odds API free tier doesn't cover these)
  markets.push({
    category: "Corners",
    options: [
      { label: "Over 8.5 corners",  odds: null, key: "corners_over_8.5"  },
      { label: "Over 9.5 corners",  odds: null, key: "corners_over_9.5"  },
      { label: "Over 10.5 corners", odds: null, key: "corners_over_10.5" },
      { label: "Under 9.5 corners", odds: null, key: "corners_under_9.5" },
    ],
  });

  markets.push({
    category: "Cards",
    options: [
      { label: "Over 1.5 cards",  odds: null, key: "cards_over_1.5"  },
      { label: "Over 2.5 cards",  odds: null, key: "cards_over_2.5"  },
      { label: "Over 3.5 cards",  odds: null, key: "cards_over_3.5"  },
      { label: "Under 2.5 cards", odds: null, key: "cards_under_2.5" },
    ],
  });

  return markets;
}

function formatOutcomeName(name, home, away) {
  if (name === home)  return `${name} win`;
  if (name === away)  return `${name} win`;
  if (name === "Draw") return "Draw";
  return name;
}

function getDefaultMarkets() {
  return [
    {
      category: "Match result",
      options: [
        { label: "Home win", odds: null, key: "h2h:home" },
        { label: "Draw",     odds: null, key: "h2h:draw" },
        { label: "Away win", odds: null, key: "h2h:away" },
      ],
    },
    {
      category: "Goals",
      options: [
        { label: "Over 1.5 goals",  odds: null, key: "totals:over_1.5"  },
        { label: "Over 2.5 goals",  odds: null, key: "totals:over_2.5"  },
        { label: "Over 3.5 goals",  odds: null, key: "totals:over_3.5"  },
        { label: "Under 2.5 goals", odds: null, key: "totals:under_2.5" },
      ],
    },
    {
      category: "Both teams to score",
      options: [
        { label: "Both score", odds: null, key: "btts:yes" },
        { label: "Not both",   odds: null, key: "btts:no"  },
      ],
    },
    {
      category: "Corners",
      options: [
        { label: "Over 8.5 corners",  odds: null, key: "corners_over_8.5"  },
        { label: "Over 9.5 corners",  odds: null, key: "corners_over_9.5"  },
        { label: "Over 10.5 corners", odds: null, key: "corners_over_10.5" },
        { label: "Under 9.5 corners", odds: null, key: "corners_under_9.5" },
      ],
    },
    {
      category: "Cards",
      options: [
        { label: "Over 1.5 cards",  odds: null, key: "cards_over_1.5"  },
        { label: "Over 2.5 cards",  odds: null, key: "cards_over_2.5"  },
        { label: "Over 3.5 cards",  odds: null, key: "cards_over_3.5"  },
        { label: "Under 2.5 cards", odds: null, key: "cards_under_2.5" },
      ],
    },
  ];
}
