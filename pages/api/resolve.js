import { createClient } from "@supabase/supabase-js";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

function calcPointsWin(odds, confidence, difficultyMultiplier) {
  const o = parseFloat(odds) || 2.0;
  const c = parseFloat(confidence) || 50;
  const d = parseFloat(difficultyMultiplier) || 1.0;
  return Math.round(o * (c / 100) * d * 10);
}

function calcPointsLoss(confidence, difficultyMultiplier) {
  const c = parseFloat(confidence) || 50;
  const d = parseFloat(difficultyMultiplier) || 1.0;
  return Math.round((c / 100) * d * 5);
}

function getStreakMultiplier(streak) {
  const s = parseInt(streak) || 0;
  if (s >= 5) return 2.0;
  if (s >= 3) return 1.5;
  return 1.0;
}

function updateDailyStreak(profile) {
  const today        = new Date().toISOString().split("T")[0]; // YYYY-MM-DD
  const lastPickDate = profile.last_pick_date;

  // Already picked today — no change
  if (lastPickDate === today) {
    return {
      daily_streak:      profile.daily_streak      || 0,
      best_daily_streak: profile.best_daily_streak || 0,
      last_pick_date:    today,
      dailyStreakChanged: false,
    };
  }

  const yesterday = new Date();
  yesterday.setDate(yesterday.getDate() - 1);
  const yesterdayStr = yesterday.toISOString().split("T")[0];

  let newDailyStreak = 1;

  if (lastPickDate === yesterdayStr) {
    // Picked yesterday — extend the streak
    newDailyStreak = (profile.daily_streak || 0) + 1;
  } else {
    // Missed a day or first pick ever — reset to 1
    newDailyStreak = 1;
  }

  const newBestDailyStreak = Math.max(profile.best_daily_streak || 0, newDailyStreak);

  return {
    daily_streak:      newDailyStreak,
    best_daily_streak: newBestDailyStreak,
    last_pick_date:    today,
    dailyStreakChanged: true,
  };
}

export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const { pickId, result } = req.body;

  if (!pickId || !["correct", "wrong"].includes(result)) {
    return res.status(400).json({ error: "Invalid request" });
  }

  const { data: pick, error: pickError } = await supabase
    .from("picks").select("*").eq("id", pickId).single();

  if (pickError || !pick) return res.status(404).json({ error: "Pick not found" });
  if (pick.result !== "pending") return res.status(400).json({ error: "Pick already resolved" });

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("current_streak, best_streak, weekly_points, total_points, daily_streak, best_daily_streak, last_pick_date")
    .eq("id", pick.user_id)
    .single();

  if (profileError || !profile) {
    return res.status(500).json({ error: "Could not find user profile" });
  }

  const currentStreak = parseInt(profile.current_streak) || 0;
  const bestStreak    = parseInt(profile.best_streak)    || 0;
  const diffMult      = parseFloat(pick.difficulty_multiplier) || 1.0;

  // Win streak
  let newStreak   = 0;
  let multiplier  = 1.0;
  let basePoints  = 0;
  let finalPoints = 0;

  if (result === "correct") {
    newStreak   = currentStreak + 1;
    multiplier  = getStreakMultiplier(newStreak);
    basePoints  = calcPointsWin(pick.odds, pick.confidence, diffMult);
    finalPoints = Math.round(basePoints * multiplier);
  } else {
    newStreak   = 0;
    multiplier  = 1.0;
    basePoints  = calcPointsLoss(pick.confidence, diffMult);
    finalPoints = -basePoints;
  }

  const newBest         = Math.max(bestStreak, newStreak);
  const newWeeklyPoints = (parseInt(profile.weekly_points) || 0) + finalPoints;
  const newTotalPoints  = (parseInt(profile.total_points)  || 0) + finalPoints;

  // Daily streak
  const dailyUpdate = updateDailyStreak(profile);

  // Update pick
  await supabase.from("picks").update({
    result,
    points_earned:            finalPoints,
    streak_multiplier:        multiplier,
    points_before_multiplier: result === "correct" ? basePoints : null,
  }).eq("id", pickId);

  // Update profile
  await supabase.from("profiles").update({
    current_streak:    newStreak,
    best_streak:       newBest,
    weekly_points:     newWeeklyPoints,
    total_points:      newTotalPoints,
    daily_streak:      dailyUpdate.daily_streak,
    best_daily_streak: dailyUpdate.best_daily_streak,
    last_pick_date:    dailyUpdate.last_pick_date,
  }).eq("id", pick.user_id);

  return res.status(200).json({
    pointsEarned:      finalPoints,
    basePoints,
    multiplier,
    newStreak,
    newBest,
    dailyStreak:       dailyUpdate.daily_streak,
    bestDailyStreak:   dailyUpdate.best_daily_streak,
    dailyStreakChanged: dailyUpdate.dailyStreakChanged,
  });
}