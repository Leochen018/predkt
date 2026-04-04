// ─── Scoring functions (inlined to avoid import issues) ───────────
function calcPointsWin(odds, confidence, difficultyMultiplier) {
  const o = odds || 2.0;
  return Math.round(o * (confidence / 100) * difficultyMultiplier * 10);
}

function calcPointsLoss(confidence, difficultyMultiplier) {
  return Math.round((confidence / 100) * difficultyMultiplier * 5);
}

// ─── Streak multipliers ───────────────────────────────────────────
export function getStreakMultiplier(streak) {
  if (streak >= 5) return 2.0;
  if (streak >= 3) return 1.5;
  return 1.0;
}

export function getStreakLabel(streak) {
  if (streak >= 5) return { label: `${streak} streak`, color: "#ef4444" };
  if (streak >= 3) return { label: `${streak} streak`, color: "#f59e0b" };
  if (streak >= 1) return { label: `${streak} streak`, color: "#22c55e" };
  return null;
}

// ─── Apply streak to a resolved pick ─────────────────────────────
export async function applyStreakAndPoints(supabase, pick, result) {
  const { data: profile } = await supabase
    .from("profiles")
    .select("current_streak, best_streak, weekly_points, total_points")
    .eq("id", pick.user_id)
    .single();

  const currentStreak = profile?.current_streak || 0;
  const bestStreak    = profile?.best_streak    || 0;
  const mult          = pick.difficulty_multiplier || 1.0;

  let newStreak   = 0;
  let multiplier  = 1.0;
  let basePoints  = 0;
  let finalPoints = 0;

  if (result === "correct") {
    newStreak   = currentStreak + 1;
    multiplier  = getStreakMultiplier(newStreak);
    basePoints  = calcPointsWin(pick.odds, pick.confidence, mult);
    finalPoints = Math.round(basePoints * multiplier);
  } else {
    newStreak   = 0;
    multiplier  = 1.0;
    basePoints  = calcPointsLoss(pick.confidence, mult);
    finalPoints = -basePoints;
  }

  const newBest = Math.max(bestStreak, newStreak);

  await supabase.from("profiles").update({
    current_streak: newStreak,
    best_streak:    newBest,
    weekly_points:  (profile?.weekly_points || 0) + finalPoints,
    total_points:   (profile?.total_points  || 0) + finalPoints,
  }).eq("id", pick.user_id);

  await supabase.from("picks").update({
    result,
    points_earned:            finalPoints,
    streak_multiplier:        multiplier,
    points_before_multiplier: result === "correct" ? basePoints : null,
  }).eq("id", pick.id);

  return { newStreak, newBest, multiplier, finalPoints, basePoints };
}