import { createClient } from "@supabase/supabase-js";
import { calcPointsWin, calcPointsLoss } from "../../lib/scoring";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

function getStreakMultiplier(streak) {
  if (streak >= 5) return 2.0;
  if (streak >= 3) return 1.5;
  return 1.0;
}

export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).json({ error: "Method not allowed" });

  const { picks, result, perPickResults } = req.body;
  if (!picks) return res.status(400).json({ error: "Missing picks" });

  // Fetch current streaks for all affected users in one query
  const userIds = [...new Set(picks.map(p => p.user_id))];
  const { data: profiles } = await supabase
    .from("profiles")
    .select("id, username, current_streak")
    .in("id", userIds);

  const streakMap = {};
  (profiles || []).forEach(p => { streakMap[p.id] = p.current_streak || 0; });

  // Track running streak per user as we process picks
  const runningStreak = { ...streakMap };

  const simulated = picks.map(p => {
    const pickResult = (perPickResults && perPickResults[p.id]) || result || "correct";
    const mult       = p.difficulty_multiplier || 1.0;
    const userId     = p.user_id;

    let finalPoints  = 0;
    let basePoints   = 0;
    let streakMult   = 1.0;
    let newStreak    = runningStreak[userId] || 0;

    if (pickResult === "correct") {
      newStreak   = (runningStreak[userId] || 0) + 1;
      streakMult  = getStreakMultiplier(newStreak);
      basePoints  = calcPointsWin(p.odds, p.confidence, mult);
      finalPoints = Math.round(basePoints * streakMult);
    } else {
      newStreak   = 0;
      basePoints  = calcPointsLoss(p.confidence, mult);
      finalPoints = -basePoints;
    }

    runningStreak[userId] = newStreak;

    return {
      id:           p.id,
      username:     p.profiles?.username ?? "Unknown",
      market:       p.market,
      match:        p.match,
      confidence:   p.confidence,
      odds:         p.odds,
      difficulty:   p.difficulty,
      result:       pickResult,
      basePoints:   pickResult === "correct" ? basePoints : null,
      streakBefore: streakMap[userId] || 0,
      streakAfter:  newStreak,
      streakMult,
      points:       finalPoints,
    };
  });

  res.status(200).json({ simulated });
}