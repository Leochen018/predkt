import { createClient } from "@supabase/supabase-js";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).json({ error: "Method not allowed" });

  const { code, userId } = req.body;
  if (!code || !userId) return res.status(400).json({ error: "Missing code or userId" });

  // Find the league
  const { data: league, error: leagueError } = await supabase
    .from("leagues")
    .select("*")
    .eq("invite_code", code.toUpperCase().trim())
    .single();

  if (leagueError || !league) {
    return res.status(404).json({ error: "Invalid invite code — league not found" });
  }

  // Check already a member
  const { data: existing } = await supabase
    .from("league_members")
    .select("id")
    .eq("league_id", league.id)
    .eq("user_id", userId)
    .single();

  if (existing) {
    return res.status(400).json({ error: "You are already in this league" });
  }

  // Join
  const { error: joinError } = await supabase
    .from("league_members")
    .insert({ league_id: league.id, user_id: userId });

  if (joinError) return res.status(500).json({ error: joinError.message });

  res.status(200).json({ league });
}