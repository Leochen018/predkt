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

// ─── Scoring formula (Elo-inspired, 60% reduced) ──────────────────
//
// Base = 4 pts (was 10, reduced 60%)
//
// Win  = round(base × diffMult × confWinMult)  capped per tier
// Loss = round(base × diffMult × confLossMult) capped at extreme
//
// confWinMult:   10%→0.64  50%→0.80  90%→0.96  (0.6 + conf×0.4)
// confLossMult:  10%→0.14  50%→0.35  90%→0.56  (0.1 + conf×0.25)
//
// This means:
//  - Confidence changes both reward AND penalty proportionally
//  - 90% confidence earns 50% more than 10% but also risks 4× more
//  - No arbitrary tier — the formula is transparent
//
// Point table (base 4, no streak):
//               10% conf    50% conf    90% conf
//  Easy win:    +3          +5          +8
//  Easy loss:   -1          -2          -3
//  Medium win:  +4          +6          +10  → capped
//  Extreme win: +8          +10         +16  → capped
//  Extreme loss:-2          -5          -8   → capped 8

const BASE = 4;
const TIER_CAPS = { easy: 2.0, medium: 3.5, hard: 5.0, extreme: 8.0 };

function confWinScale(confidence) {
  const c = Math.min(Math.max(parseInt(confidence) || 50, 10), 90) / 100;
  return 0.6 + c * 0.4;
}

function confLossScale(confidence) {
  const c = Math.min(Math.max(parseInt(confidence) || 50, 10), 90) / 100;
  return 0.1 + c * 0.25;
}

export function calcPointsWin(odds, confidence, difficultyMultiplier, diffKey) {
  const d   = parseFloat(difficultyMultiplier) || 1.0;
  const cs  = confWinScale(confidence);
  const raw = Math.round(BASE * d * cs);
  const cap = Math.round(BASE * d * (TIER_CAPS[diffKey] || 2.0));
  return Math.min(raw, cap);
}

export function calcPointsWinCapped(odds, confidence, diffKey) {
  const tier = DIFFICULTY[diffKey] || DIFFICULTY.easy;
  return calcPointsWin(odds, confidence, tier.multiplier, diffKey);
}

export function calcPointsLoss(confidence, difficultyMultiplier, diffKey) {
  const d   = parseFloat(difficultyMultiplier) || 1.0;
  const cs  = confLossScale(confidence);
  const cap = diffKey === "extreme" ? 8 : 99;
  return Math.min(Math.round(BASE * d * cs), cap);
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

export function getPointsBreakdown(odds, confidence, diffKey) {
  const tier = DIFFICULTY[diffKey] || DIFFICULTY.easy;
  const win  = calcPointsWin(odds, confidence, tier.multiplier, diffKey);
  const loss = calcPointsLoss(confidence, tier.multiplier, diffKey);
  const cap  = Math.round(BASE * tier.multiplier * (TIER_CAPS[diffKey] || 2.0));
  return { win, loss, wasCapped: win >= cap, cap };
}

// ─── Formula explanation text for UI modal ────────────────────────
export function getFormulaExplanation(confidence, diffKey) {
  const tier  = DIFFICULTY[diffKey] || DIFFICULTY.easy;
  const conf  = parseInt(confidence) || 70;
  const steps = [10, 30, 50, 70, 90].map(c => ({
    conf: c,
    win:  calcPointsWin(null, c, tier.multiplier, diffKey),
    loss: calcPointsLoss(c, tier.multiplier, diffKey),
  }));
  return {
    formula:      `Win = 4 × ${tier.multiplier} × (0.6 + confidence × 0.4)`,
    lossFormula:  `Loss = 4 × ${tier.multiplier} × (0.1 + confidence × 0.25)`,
    tierLabel:    tier.label,
    tierMult:     tier.multiplier,
    tierColor:    tier.color,
    cap:          Math.round(BASE * tier.multiplier * (TIER_CAPS[diffKey] || 2.0)),
    steps,
    currentWin:   calcPointsWin(null, conf, tier.multiplier, diffKey),
    currentLoss:  calcPointsLoss(conf, tier.multiplier, diffKey),
  };
}