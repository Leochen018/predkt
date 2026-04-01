// ─── Difficulty tiers ─────────────────────────────────────────────
export const DIFFICULTY = {
  easy: {
    label:      "Easy",
    multiplier: 1.0,
    color:      "#22c55e",
    markets:    [
      "home win", "away win", "draw",
      "over 1.5 goals", "under 1.5 goals",
      "over 2.5 goals", "under 2.5 goals",
      "over 3.5 goals", "under 3.5 goals",
    ],
  },
  medium: {
    label:      "Medium",
    multiplier: 1.5,
    color:      "#f59e0b",
    markets:    [
      "both score", "not both",
      "over 8.5 corners", "over 9.5 corners", "over 10.5 corners", "under 9.5 corners",
      "over 1.5 cards",   "over 2.5 cards",   "over 3.5 cards",   "under 2.5 cards",
    ],
  },
  hard: {
    label:      "Hard",
    multiplier: 2.5,
    color:      "#ef4444",
    markets:    [
      "correct score", "first goalscorer", "anytime scorer", "last goalscorer",
    ],
  },
};

// ─── Get difficulty for a market label ────────────────────────────
export function getDifficulty(marketLabel) {
  const lower = marketLabel.toLowerCase();
  for (const [key, tier] of Object.entries(DIFFICULTY)) {
    if (tier.markets.some(m => lower.includes(m))) {
      return { key, ...tier };
    }
  }
  return { key: "easy", ...DIFFICULTY.easy }; // default
}

// ─── Calculate points if correct ──────────────────────────────────
// points = odds × (confidence / 100) × difficulty_multiplier × 10
export function calcPointsWin(odds, confidence, difficultyMultiplier) {
  const o = odds || 2.0; // default to 2.0 if no odds
  return Math.round(o * (confidence / 100) * difficultyMultiplier * 10);
}

// ─── Calculate points lost if wrong ───────────────────────────────
// loss = (confidence / 100) × difficulty_multiplier × 5
export function calcPointsLoss(confidence, difficultyMultiplier) {
  return Math.round((confidence / 100) * difficultyMultiplier * 5);
}