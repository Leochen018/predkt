import { createClient } from "@supabase/supabase-js";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

function generateCode() {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < 6; i++) {
    code += chars[Math.floor(Math.random() * chars.length)];
  }
  return code;
}

export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).json({ error: "Method not allowed" });

  const { name, userId } = req.body;
  if (!name || !userId) return res.status(400).json({ error: "Missing name or userId" });

  // Generate a unique invite code
  let code = generateCode();
  let attempts = 0;
  while (attempts < 10) {
    const { data: existing } = await supabase
      .from("leagues").select("id").eq("invite_code", code).single();
    if (!existing) break;
    code = generateCode();
    attempts++;
  }

  // Create the league
  const { data: league, error } = await supabase
    .from("leagues")
    .insert({ name: name.trim(), creator_id: userId, invite_code: code })
    .select()
    .single();

  if (error) return res.status(500).json({ error: error.message });

  // Auto-join creator to the league
  await supabase.from("league_members").insert({
    league_id: league.id,
    user_id:   userId,
  });

  res.status(200).json({ league });
}