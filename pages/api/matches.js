export default async function handler(req, res) {
  const API_KEY = process.env.FOOTBALL_DATA_API_KEY;

  try {
    const today = new Date();
    const nextWeek = new Date(today);
    nextWeek.setDate(today.getDate() + 7);

    const dateFrom = today.toISOString().split("T")[0];
    const dateTo   = nextWeek.toISOString().split("T")[0];

    const response = await fetch(
      `https://api.football-data.org/v4/matches?dateFrom=${dateFrom}&dateTo=${dateTo}`,
      { headers: { "X-Auth-Token": API_KEY } }
    );

    if (!response.ok) {
      const err = await response.json();
      return res.status(response.status).json({ error: err.message || "Failed to fetch matches" });
    }

    const data = await response.json();
    let matches = data.matches || [];

    // Sort by kickoff time ascending
    matches.sort((a, b) => new Date(a.utcDate) - new Date(b.utcDate));

    const formatted = matches.map((m, i) => ({
      id:          i + 1,
      home:        m.homeTeam.shortName || m.homeTeam.name,
      away:        m.awayTeam.shortName || m.awayTeam.name,
      homeCrest:   m.homeTeam.crest || null,
      awayCrest:   m.awayTeam.crest || null,
      time:        formatKickoff(m.utcDate),
      competition: m.competition?.name || "",
      compCrest:   m.competition?.emblem || null,
    }));

    res.status(200).json({ matches: formatted });

  } catch (error) {
    res.status(500).json({ error: "Server error: " + error.message });
  }
}

function formatKickoff(utcDate) {
  const date     = new Date(utcDate);
  const now      = new Date();
  const tomorrow = new Date(now);
  tomorrow.setDate(tomorrow.getDate() + 1);

  const isToday    = date.toDateString() === now.toDateString();
  const isTomorrow = date.toDateString() === tomorrow.toDateString();

  const time = date.toLocaleTimeString("en-GB", {
    hour: "2-digit", minute: "2-digit", timeZone: "Europe/London",
  });

  const day = date.toLocaleDateString("en-GB", {
    weekday: "short", timeZone: "Europe/London",
  });

  const dateStr = date.toLocaleDateString("en-GB", {
    day: "numeric", month: "short", timeZone: "Europe/London",
  });

  if (isToday)    return `Today ${time}`;
  if (isTomorrow) return `Tomorrow ${time}`;
  return `${day} ${dateStr} ${time}`;
}