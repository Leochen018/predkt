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
  const today        = new Date().toISOString().split("T")[0];
  const lastPickDate = profile.last_pick_date;
  if (lastPickDate === today) {
    return { daily_streak: profile.daily_streak || 0, best_daily_streak: profile.best_daily_streak || 0, last_pick_date: today };
  }
  const yesterday = new Date();
  yesterday.setDate(yesterday.getDate() - 1);
  const yesterdayStr = yesterday.toISOString().split("T")[0];
  const newDailyStreak = lastPickDate === yesterdayStr ? (profile.daily_streak || 0) + 1 : 1;
  return {
    daily_streak:      newDailyStreak,
    best_daily_streak: Math.max(profile.best_daily_streak || 0, newDailyStreak),
    last_pick_date:    today,
  };
}

export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).json({ error: "Method not allowed" });

  const { match, homeScore, awayScore } = req.body;
  if (!match || homeScore === undefined || awayScore === undefined) {
    return res.status(400).json({ error: "Missing match or scores" });
  }

  const { data: picks, error: fetchError } = await supabase
    .from("picks").select("*").eq("match", match).eq("result", "pending");

  if (fetchError) return res.status(500).json({ error: fetchError.message });
  if (!picks || picks.length === 0) return res.status(200).json({ settled: 0, results: [] });

  const home       = parseInt(homeScore);
  const away       = parseInt(awayScore);
  const totalGoals = home + away;
  const results    = [];

  // Cache profiles to avoid duplicate fetches
  const profileCache = {};

  for (const pick of picks) {
    const market = pick.market.toLowerCase();
    let correct  = false;
    let skip     = false;

    if      (market.includes("home win"))    correct = home > away;
    else if (market.includes("away win"))    correct = away > home;
    else if (market.includes("draw"))        correct = home === away;
    else if (market.includes("over 0.5"))   correct = totalGoals > 0.5;
    else if (market.includes("under 0.5"))  correct = totalGoals < 0.5;
    else if (market.includes("over 1.5"))   correct = totalGoals > 1.5;
    else if (market.includes("under 1.5"))  correct = totalGoals < 1.5;
    else if (market.includes("over 2.5"))   correct = totalGoals > 2.5;
    else if (market.includes("under 2.5"))  correct = totalGoals < 2.5;
    else if (market.includes("over 3.5"))   correct = totalGoals > 3.5;
    else if (market.includes("under 3.5"))  correct = totalGoals < 3.5;
    else if (market.includes("both score")) correct = home > 0 && away > 0;
    else if (market.includes("not both"))   correct = home === 0 || away === 0;
    else { skip = true; }

    if (skip) { results.push({ id: pick.id, market: pick.market, skipped: true }); continue; }

    const result = correct ? "correct" : "wrong";

    // Get profile (use cache)
    if (!profileCache[pick.user_id]) {
      const { data: p } = await supabase
        .from("profiles")
        .select("current_streak, best_streak, weekly_points, total_points, daily_streak, best_daily_streak, last_pick_date")
        .eq("id", pick.user_id).single();
      profileCache[pick.user_id] = p;
    }

    const profile       = profileCache[pick.user_id];
    const currentStreak = parseInt(profile?.current_streak) || 0;
    const diffMult      = parseFloat(pick.difficulty_multiplier) || 1.0;

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
      basePoints  = calcPointsLoss(pick.confidence, diffMult);
      finalPoints = -basePoints;
    }

    const newBest    = Math.max(parseInt(profile?.best_streak) || 0, newStreak);
    const dailyUp    = updateDailyStreak(profile);

    // Update profile in cache for next pick from same user
    profileCache[pick.user_id] = {
      ...profile,
      current_streak:    newStreak,
      best_streak:       newBest,
      weekly_points:     (parseInt(profile?.weekly_points) || 0) + finalPoints,
      total_points:      (parseInt(profile?.total_points)  || 0) + finalPoints,
      daily_streak:      dailyUp.daily_streak,
      best_daily_streak: dailyUp.best_daily_streak,
      last_pick_date:    dailyUp.last_pick_date,
    };

    await supabase.from("picks").update({
      result,
      points_earned:            finalPoints,
      streak_multiplier:        multiplier,
      points_before_multiplier: result === "correct" ? basePoints : null,
    }).eq("id", pick.id);

    await supabase.from("profiles").update(profileCache[pick.user_id]).eq("id", pick.user_id);

    results.push({ id: pick.id, market: pick.market, result, pointsEarned: finalPoints, multiplier, newStreak });
  }

  const settled = results.filter(r => !r.skipped).length;
  res.status(200).json({ settled, results });
}