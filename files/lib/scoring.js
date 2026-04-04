// ─── Difficulty tiers ──────────────────────────────────────────────
export const DIFFICULTY = {
  easy: {
    label: "Easy", multiplier: 1.0, color: "#22c55e",
    markets: [
      "home win","away win","draw",
      "home or draw","home or away","draw or away",
      "over 0.5","over 1.5","under 1.5",
      "over 2.5","under 2.5","over 3.5","under 3.5",
    ],
  },
  medium: {
    label: "Medium", multiplier: 1.4, color: "#f59e0b",
    markets: [
      "both score","not both","both score 1h","not both 1h",
      "home first","away first",
      "over 4.5","under 4.5",
      "home win ht","draw ht","away win ht",
      "to nil","asian handicap","-0.5","-1.5","+0.5",
      "1h over","1h under",
    ],
  },
  hard: {
    label: "Hard", multiplier: 2.0, color: "#f97316",
    markets: [
      "exactly","exact goals",
      "over 8.5 corners","over 9.5 corners",
      "under 9.5 corners","under 8.5 corners",
      "over 1.5 cards","over 2.5 cards",
      "under 2.5 cards","under 3.5 cards",
      "ht/ft","halftime/fulltime",
    ],
  },
  extreme: {
    label: "Extreme", multiplier: 3.0, color: "#ef4444",
    markets: [
      "correct score","cs:",
      "1-0","2-0","2-1","1-1","0-0","0-1","0-2","1-2","3-0","3-1","2-2","0-3",
      "first goalscorer","anytime goalscorer","anytime scorer",
      "over 10.5 corners","over 3.5 cards","over 4.5 cards",
      "shots on target","brace","hat-trick",
    ],
  },
};

export function getDifficulty(marketLabel) {
  const lower = marketLabel.toLowerCase();
  for (const [key, tier] of Object.entries(DIFFICULTY)) {
    if (tier.markets.some(m => lower.includes(m))) return { key, ...tier };
  }
  return { key: "easy", ...DIFFICULTY.easy };
}

// ─── New scoring formula ───────────────────────────────────────────
//
// WIN  = round(4 × odds × (conf/100) × dailyBonus × streakMult)
//   dailyBonus  = 1.2 if daily_streak >= 2, else 1.0
//   streakMult  = min(1.0 + winStreak × 0.1, 2.0)
//                 0 wins→1.0  1→1.1  2→1.2 ... 10+→2.0
//
// LOSS = round(4 × odds × (conf/100) × 0.5)
//   No streak or daily bonus on loss
//
// Example — odds 2.5, 70% conf, 3-win streak, daily bonus:
//   Win:  4 × 2.5 × 0.70 × 1.2 × 1.3 = 10.9 → 11 pts
//   Loss: 4 × 2.5 × 0.70 × 0.5         = 3.5 → 4 pts

const BASE = 4;

export function getStreakMultiplier(winStreak) {
  const s = Math.max(0, parseInt(winStreak) || 0);
  return Math.min(1.0 + s * 0.1, 2.0);
}

export function getDailyBonus(dailyStreak) {
  return (parseInt(dailyStreak) || 0) >= 2 ? 1.2 : 1.0;
}

export function calcPointsWin(odds, confidence, winStreak, dailyStreak) {
  const o    = parseFloat(odds) || 1.0;
  const c    = Math.min(Math.max(parseInt(confidence) || 50, 0), 100) / 100;
  const sm   = getStreakMultiplier(winStreak);
  const db   = getDailyBonus(dailyStreak);
  return Math.max(1, Math.round(BASE * o * c * db * sm));
}

export function calcPointsLoss(odds, confidence) {
  const o = parseFloat(odds) || 1.0;
  const c = Math.min(Math.max(parseInt(confidence) || 50, 0), 100) / 100;
  return Math.max(1, Math.round(BASE * o * c * 0.5));
}


export function getValueLabel(odds) {
  if (!odds) return null;
  if (odds >= 8)   return { label: "Jackpot",   color: "#a855f7" };
  if (odds >= 4)   return { label: "Long shot", color: "#ef4444" };
  if (odds >= 2.5) return { label: "Risky",     color: "#f97316" };
  if (odds >= 1.7) return { label: "Fair",      color: "#f59e0b" };
  if (odds >= 1.3) return { label: "Safe",      color: "#22c55e" };
  return               { label: "Banker",    color: "#22c55e" };
}

export function getPointsBreakdown(odds, confidence, winStreak, dailyStreak) {
  const win  = calcPointsWin(odds, confidence, winStreak, dailyStreak);
  const loss = calcPointsLoss(odds, confidence);
  return { win, loss };
}

export function getFormulaExplanation(odds, confidence, winStreak, dailyStreak) {
  const sm  = getStreakMultiplier(winStreak);
  const db  = getDailyBonus(dailyStreak);
  const win  = calcPointsWin(odds, confidence, winStreak, dailyStreak);
  const loss = calcPointsLoss(odds, confidence);
  return {
    formula:     `Win = 4 × ${odds ?? "odds"} × ${confidence}% × ${db}daily × ${sm}streak`,
    lossFormula: `Loss = 4 × ${odds ?? "odds"} × ${confidence}% × 0.5`,
    streakMult:  sm,
    dailyBonus:  db,
    win,
    loss,
  };
}
