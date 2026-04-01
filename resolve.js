import { createClient } from "@supabase/supabase-js";
import { calcPointsWin, calcPointsLoss } from "../../lib/scoring";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).json({ error: "Method not allowed" });

  const { pickId, result } = req.body;

  if (!pickId || !["correct", "wrong"].includes(result)) {
    return res.status(400).json({ error: "Invalid request" });
  }

  // Get the pick
  const { data: pick, error: pickError } = await supabase
    .from("picks")
    .select("*")
    .eq("id", pickId)
    .single();

  if (pickError || !pick) return res.status(404).json({ error: "Pick not found" });
  if (pick.result !== "pending") return res.status(400).json({ error: "Pick already resolved" });

  // Calculate points
  const mult         = pick.difficulty_multiplier || 1.0;
  const pointsEarned = result === "correct"
    ? calcPointsWin(pick.odds, pick.confidence, mult)
    : -calcPointsLoss(pick.confidence, mult);

  // Update the pick
  const { error: updateError } = await supabase
    .from("picks")
    .update({ result, points_earned: pointsEarned })
    .eq("id", pickId);

  if (updateError) return res.status(500).json({ error: updateError.message });

  // Get current profile points
  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("weekly_points, total_points")
    .eq("id", pick.user_id)
    .single();

  if (profileError) return res.status(500).json({ error: profileError.message });

  // Update profile points
  const { error: pointsError } = await supabase
    .from("profiles")
    .update({
      weekly_points: (profile.weekly_points || 0) + pointsEarned,
      total_points:  (profile.total_points  || 0) + pointsEarned,
    })
    .eq("id", pick.user_id);

  if (pointsError) return res.status(500).json({ error: pointsError.message });

  res.status(200).json({ success: true, pointsEarned });
}
