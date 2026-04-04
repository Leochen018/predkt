import { useState, useEffect, useMemo, useRef } from "react";
import { supabase } from "./lib/supabase";
import { getDifficulty, calcPointsWin, calcPointsLoss, getValueLabel, calcPointsWinCapped, getPointsBreakdown, getFormulaExplanation } from "./lib/scoring";
import { fetchMatches as fetchMatchesAPI, fetchOdds as fetchOddsAPI } from "./lib/clientApi";
import { requestNotificationPermission, scheduleMatchReminder } from "./lib/notifications";

// ─── Streak helpers (inline to avoid server-only import issues) ───
function getStreakMultiplier(streak) {
  if (streak >= 5) return 2.0;
  if (streak >= 3) return 1.5;
  return 1.0;
}
function getStreakLabel(streak) {
  if (streak >= 5) return { label: streak + " streak", color: "#ef4444" };
  if (streak >= 3) return { label: streak + " streak", color: "#f59e0b" };
  if (streak >= 1) return { label: streak + " streak", color: "#22c55e" };
  return null;
}

// Defined outside component — static data, never needs to be recreated
const QUICK_BUILDERS = [
  { name: "BTTS & Over 2.5",    emoji: "⚽", desc: "Both score, 3+ goals",         picks: ["btts:yes", "totals:over_2.5"] },
  { name: "Home Win & BTTS",     emoji: "🏠", desc: "Home win, both score",          picks: ["h2h:home", "btts:yes"] },
  { name: "Away Win & BTTS",     emoji: "✈️", desc: "Away win, both score",          picks: ["h2h:away", "btts:yes"] },
  { name: "Draw & BTTS",         emoji: "🤝", desc: "Goalful draw",                  picks: ["h2h:draw", "btts:yes"] },
  { name: "Home Nil & Win",      emoji: "🔒", desc: "Home clean sheet",              picks: ["wtn:home", "h2h:home"] },
  { name: "Away Nil & Win",      emoji: "🛡️", desc: "Away clean sheet",             picks: ["wtn:away", "h2h:away"] },
  { name: "Over 2.5 Goals",      emoji: "🔥", desc: "3 or more goals in game",       picks: ["totals:over_2.5"] },
  { name: "Over 3.5 Goals",      emoji: "💥", desc: "4+ goals, action packed",       picks: ["totals:over_3.5"] },
  { name: "Under 2.5 Goals",     emoji: "🧱", desc: "Tight, low scoring affair",     picks: ["totals:under_2.5"] },
  { name: "Goals & Corners",     emoji: "📐", desc: "Over 2.5 goals + corners",      picks: ["totals:over_2.5", "corners_over_9.5"] },
  { name: "Home HT Lead",        emoji: "⏱️", desc: "Home ahead at half time",       picks: ["ht:home", "h2h:home"] },
  { name: "HT Draw to Home Win", emoji: "🔄", desc: "Level at HT, home wins",        picks: ["ht:draw", "h2h:home"] },
  { name: "Home Win to Nil",     emoji: "🚫", desc: "Home win, away don't score",    picks: ["h2h:home", "totals:under_2.5"] },
  { name: "Both Teams & Corners",emoji: "🎯", desc: "Goals + corner action",         picks: ["btts:yes", "corners_over_9.5"] },
  { name: "Away Upset",          emoji: "😤", desc: "Away win against the odds",     picks: ["h2h:away", "totals:over_1.5"] },
  { name: "Action Packed",       emoji: "🎆", desc: "Cards, corners & goals",        picks: ["totals:over_2.5", "cards_over_2.5", "corners_over_9.5"] },
];

// Loose team-name matcher — handles "Man City" vs "Manchester City", case differences, FC suffix, etc.
function teamsMatch(a, b) {
  if (!a || !b) return false;
  const norm = s => s.toLowerCase().replace(/\s*f\.?c\.?\s*$/i, "").replace(/\./g, "").trim();
  const na = norm(a), nb = norm(b);
  return na === nb || na.includes(nb) || nb.includes(na);
}
function findLiveMatch(liveMatches, home, away, fixtureId) {
  return liveMatches.find(lm =>
    lm.fixtureId === fixtureId ||
    (teamsMatch(lm.home, home) && teamsMatch(lm.away, away))
  ) || null;
}

export default function App() {
  // Auth
  const [user,          setUser]          = useState(null);
  const [authScreen,    setAuthScreen]    = useState("welcome"); // "welcome"|"guest"|"login"|"signup"|"verify"|"upgrade"
  const [email,         setEmail]         = useState("");
  const [password,      setPassword]      = useState("");
  const [guestName,     setGuestName]     = useState("");
  const [username,      setUsername]      = useState("");
  const [authError,     setAuthError]     = useState("");
  const [authLoading,   setAuthLoading]   = useState(false);
  const [upgradePrompt, setUpgradePrompt] = useState(null); // null | "streak" | "social" | "league" | "expired"
  // Derived from profile — is the current user anonymous?
  // profile.is_anonymous is set to true when signed in anonymously

  // App
  const [screen,         setScreen]         = useState("feed");
  const [calendarPicks,  setCalendarPicks]  = useState({}); // { "2025-04-01": true }
  const [liveMatches,    setLiveMatches]    = useState([]); // live fixture statuses
  const [matches,        setMatches]        = useState([]);
  const [matchesLoading, setMatchesLoading] = useState(false);
  const [matchesError,   setMatchesError]   = useState("");
  const [matchSearch,    setMatchSearch]    = useState("");
  const [selectedDate,   setSelectedDate]   = useState(() => new Date().toISOString().split("T")[0]);
  const [predictView,    setPredictView]    = useState("list"); // "list" | "detail"
  const [marketTab,      setMarketTab]      = useState(0); // active category tab index
  const [match,          setMatch]          = useState(null);
  const [markets,        setMarkets]        = useState([]);
  const [marketsLoading, setMarketsLoading] = useState(false);
  const [oddsLive,       setOddsLive]       = useState(false);
  const [betslip,        setBetslip]        = useState([]);  // array of picks for accumulator
  const [slipOpen,       setSlipOpen]       = useState(false);
  const [slipError,      setSlipError]      = useState("");
  const [slipMode,       setSlipMode]       = useState("single"); // "single" | "acca"
  const [notifyOnPick,   setNotifyOnPick]   = useState(false);
  const [selectedMarket, setSelectedMarket] = useState(null);
  const [conf,           setConf]           = useState(70);
  const [formulaModal,   setFormulaModal]   = useState(null);
  const [feed,           setFeed]           = useState([]);
  const [myPicks,        setMyPicks]        = useState([]);
  const [profile,        setProfile]        = useState(null);
  const [loading,        setLoading]        = useState(false);
  const [error,          setError]          = useState("");

  // Profile
  const [viewingProfile,  setViewingProfile]  = useState(null); // null = own profile
  const [profileData,     setProfileData]     = useState(null);
  const [profilePicks,    setProfilePicks]    = useState([]);
  const [followerCount,   setFollowerCount]   = useState(0);
  const [followingCount,  setFollowingCount]  = useState(0);
  const [isFollowing,     setIsFollowing]     = useState(false);
  const [followLoading,   setFollowLoading]   = useState(false);
  const [profileLoading,  setProfileLoading]  = useState(false);
  const [editMode,        setEditMode]        = useState(false);
  const [editUsername,    setEditUsername]    = useState("");
  const [editFavTeam,     setEditFavTeam]     = useState(""); // autocomplete input
  const [editFavTeamsList,setEditFavTeamsList]= useState([]); // selected teams array
  const [editFavLeague,     setEditFavLeague]     = useState(""); // autocomplete input
  const [editFavLeaguesList,setEditFavLeaguesList]= useState([]); // selected leagues array
  const [teamSuggestions,   setTeamSuggestions]   = useState([]);
  const [leagueSuggestions, setLeagueSuggestions] = useState([]);
  const [showTeamDrop,      setShowTeamDrop]      = useState(false);
  const [showLeagueDrop,    setShowLeagueDrop]    = useState(false);
  const [editSaving,      setEditSaving]      = useState(false);
  const [editError,       setEditError]       = useState("");

  // Pick management
  const [deletingPickId, setDeletingPickId] = useState(null);
  const [editingPickId,  setEditingPickId]  = useState(null);
  const [editPickConf,   setEditPickConf]   = useState(70);

  // Pre-loaded H/D/A odds for match list cards — keyed by fixtureId
  const [matchOdds, setMatchOdds] = useState({}); // { [fixtureId]: options[] | null }

  // Leaderboard
  const [lbTab,     setLbTab]     = useState("weekly");
  const [lbData,    setLbData]    = useState([]);
  const [lbLoading, setLbLoading] = useState(false);

  // Leagues
  const [myLeagues,       setMyLeagues]       = useState([]);
  const [leagueLoading,   setLeagueLoading]   = useState(false);
  const [leagueView,      setLeagueView]      = useState(null); // null = list, league object = detail
  const [leagueMembers,   setLeagueMembers]   = useState([]);
  const [leagueMembLoad,  setLeagueMembLoad]  = useState(false);
  const [createName,      setCreateName]      = useState("");
  const [joinCode,        setJoinCode]        = useState("");
  const [leagueMsg,       setLeagueMsg]       = useState({ text: "", ok: true });
  const [leagueAction,    setLeagueAction]    = useState("list"); // "list"|"create"|"join"
  const [leagueActLoading,setLeagueActLoading]= useState(false);
  const [copied,          setCopied]          = useState(false);
  const [inviteEmail,     setInviteEmail]     = useState("");
  const [inviteLoading,   setInviteLoading]   = useState(false);
  const [inviteMsg,       setInviteMsg]       = useState({ text: "", ok: true });

  // Admin
  const [adminTab,      setAdminTab]      = useState("settle");
  const [adminPicks,    setAdminPicks]    = useState([]);
  const [adminLoading,  setAdminLoading]  = useState(false);
  const [resolvingId,   setResolvingId]   = useState(null);
  const [adminMsg,      setAdminMsg]      = useState({ text: "", ok: true });
  const [settleMatch,   setSettleMatch]   = useState("");
  const [homeScore,     setHomeScore]     = useState("");
  const [awayScore,     setAwayScore]     = useState("");
  const [settleLoading, setSettleLoading] = useState(false);
  const [settleResult,  setSettleResult]  = useState(null);
  const [simPicks,      setSimPicks]      = useState([]);
  const [simResult,     setSimResult]     = useState("correct");
  const [perPickResults, setPerPickResults] = useState({});
  const [simLoading,    setSimLoading]    = useState(false);
  const [simOutput,     setSimOutput]     = useState(null);
  const [simLeaderboard, setSimLeaderboard] = useState(null);
  const [simMatch,      setSimMatch]      = useState("");

  const isAdmin = profile?.role === "admin";

  // Search
  const [searchQuery,   setSearchQuery]   = useState("");
  const [searchResults, setSearchResults] = useState([]);
  const [searchLoading, setSearchLoading] = useState(false);
  const [showSearch,    setShowSearch]    = useState(false);

  // ── Debounce ref for user search (prevents DB call on every keystroke) ──
  const searchTimerRef = useRef(null);

  // ── Memoised derivations — only recompute when their inputs change ──

  // Parse fav teams once per profile change, not on every render
  const favTeams = useMemo(
    () => (profile?.favourite_team || "").split("|").map(t => t.trim().toLowerCase()).filter(Boolean),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [profile?.favourite_team]
  );
  const favLeagues = useMemo(
    () => (profile?.favourite_league || "").split("|").map(l => l.trim().toLowerCase()).filter(Boolean),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [profile?.favourite_league]
  );

  // Match count per date — O(n) once when matches load, not O(14n) per render
  const dateMatchCounts = useMemo(() => {
    const m = {};
    matches.forEach(f => { const d = f.rawDate?.split("T")[0]; if (d) m[d] = (m[d] || 0) + 1; });
    return m;
  }, [matches]);

  // Unique team / league name lists for profile autocomplete
  const allTeamNames = useMemo(
    () => [...new Set(matches.flatMap(m => [m.home, m.away]))].sort(),
    [matches]
  );
  const allLeagueNames = useMemo(
    () => [...new Set(matches.map(m => m.competition).filter(Boolean))].sort(),
    [matches]
  );

  // Filtered + grouped + sorted match list for the predict view
  const predictList = useMemo(() => {
    const q = matchSearch.toLowerCase().trim();
    const isFavLeagueComp = comp => favLeagues.some(l => (comp || "").toLowerCase().includes(l));
    const isFavTeamMatch  = m => favTeams.some(t => m.home.toLowerCase().includes(t) || m.away.toLowerCase().includes(t));

    const dateFiltered = q
      ? matches
      : matches.filter(m => m.rawDate?.split("T")[0] === selectedDate);

    const filtered = q
      ? dateFiltered.filter(m =>
          m.home.toLowerCase().includes(q) ||
          m.away.toLowerCase().includes(q) ||
          (m.competition || "").toLowerCase().includes(q))
      : dateFiltered;

    const favMatches = !q && favTeams.length > 0 ? filtered.filter(isFavTeamMatch) : [];

    const grouped = {};
    filtered.forEach(m => {
      const c = m.competition || "Other";
      if (!grouped[c]) grouped[c] = [];
      grouped[c].push(m);
    });
    const entries = Object.entries(grouped);
    entries.sort(([a], [b]) => {
      const aF = isFavLeagueComp(a); const bF = isFavLeagueComp(b);
      if (aF && !bF) return -1; if (!aF && bF) return 1; return 0;
    });
    if (favTeams.length) {
      entries.forEach(([, ms]) => ms.sort((a, b) => {
        const aF = isFavTeamMatch(a); const bF = isFavTeamMatch(b);
        if (aF && !bF) return -1; if (!aF && bF) return 1; return 0;
      }));
    }
    return { q, filtered, favMatches, entries, isFavLeagueComp, isFavTeamMatch };
  }, [matches, matchSearch, selectedDate, favTeams, favLeagues]);

  // ── Session ────────────────────────────────────────────────────
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setUser(data?.session?.user ?? null);
    });
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
    });
    return () => subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (user) { loadFeed(); loadMyPicks(); loadProfile(); loadCalendarPicks(); }
  }, [user]);

  // Poll live match statuses every 60 seconds
  useEffect(() => {
    if (!user) return;
    const pollLive = async () => {
      try {
        const res  = await fetchfetch("http://192.168.0.5:3001/api/live");
        const data = await res.json();
        if (data.liveMatches) setLiveMatches(data.liveMatches);
      } catch {}
    };
    pollLive();
    const interval = setInterval(pollLive, 60000);
    return () => clearInterval(interval);
  }, [user]);

  useEffect(() => {
    if (screen === "predict") { if (matches.length === 0) loadMatches(); setPredictView("list"); setMatchSearch(""); setSelectedDate(new Date().toISOString().split("T")[0]); setSelectedMarket(null); setBetslip([]); setSlipOpen(false); setSlipMode("single"); setMatchOdds({}); }
    if (screen === "admin")       loadAdminPicks();
    if (screen === "leaderboard") loadLeaderboard(lbTab); // guests can view leaderboard
    if (screen === "profile" && user) loadProfileScreen(viewingProfile);
    if (screen === "calendar" && user) loadCalendarPicks();
    if (screen === "leagues" && user) loadMyLeagues();
  }, [screen]);

  useEffect(() => {
    if (screen === "leaderboard") loadLeaderboard(lbTab); // guests can view leaderboard
  }, [lbTab]);

  useEffect(() => {
    if (match) loadOdds(match);
  }, [match]);

  useEffect(() => {
    if (screen === "predict" && matches.length > 0) loadH2HOddsForDate(selectedDate);
  }, [selectedDate, matches]);

  const difficulty      = selectedMarket ? getDifficulty(selectedMarket.label) : null;
  const streakCount     = profile?.current_streak || 0;
  const streakMult      = getStreakMultiplier(streakCount + 1);
  const basePointsToWin = selectedMarket ? calcPointsWinCapped(selectedMarket.odds, conf, difficulty?.key) : 0;
  const pointsToWin     = Math.round(basePointsToWin * streakMult);
  const pointsToLose    = selectedMarket ? calcPointsLoss(conf, difficulty?.multiplier || 1, difficulty?.key) : 0;
  const pointsBreakdown = selectedMarket ? getPointsBreakdown(selectedMarket.odds, conf, difficulty?.key) : null;

  // ── Profile screen loader ──────────────────────────────────────
  async function openProfile(profileId) {
    if (!user && !profileId) return;
    setViewingProfile(profileId || null);
    setScreen("profile");
  }

  async function loadProfileScreen(profileId) {
    if (!user) return; // guest mode — no server profile
    setProfileLoading(true);
    const targetId = profileId || user?.id;

    // Load profile data
    const { data: pd } = await supabase
      .from("profiles").select("*").eq("id", targetId).single();
    setProfileData(pd);

    // Load picks
    const { data: picks } = await supabase
      .from("picks").select("*").eq("user_id", targetId)
      .order("created_at", { ascending: false }).limit(10);
    setProfilePicks(picks || []);

    // Follower count
    const { count: fc } = await supabase
      .from("follows").select("*", { count: "exact", head: true })
      .eq("following_id", targetId);
    setFollowerCount(fc || 0);

    // Following count
    const { count: fg } = await supabase
      .from("follows").select("*", { count: "exact", head: true })
      .eq("follower_id", targetId);
    setFollowingCount(fg || 0);

    // Am I following this person?
    if (profileId && profileId !== user?.id) {
      const { data: followData } = await supabase
        .from("follows").select("id")
        .eq("follower_id", user?.id)
        .eq("following_id", profileId)
        .single();
      setIsFollowing(!!followData);
    }

    setProfileLoading(false);
  }

  async function handleSaveProfile() {
    if (!editUsername.trim()) { setEditError("Username cannot be empty"); return; }
    setEditSaving(true); setEditError("");
    const { error } = await supabase
      .from("profiles")
      .update({
        username:         editUsername.trim(),
        favourite_team:   editFavTeamsList.length > 0   ? editFavTeamsList.join("|")   : null,
        favourite_league: editFavLeaguesList.length > 0 ? editFavLeaguesList.join("|") : null,
      })
      .eq("id", user?.id);
    if (error) { setEditError(error.message); }
    else {
      await loadProfile();
      await loadProfileScreen(null);
      setEditMode(false);
    }
    setEditSaving(false);
  }

  async function handleFollow() {
    if (!user) { requireAccount("social"); return; }
    if (profile?.is_anonymous) { requireAccount("social"); return; }
    if (!viewingProfile || viewingProfile === user?.id) return;
    setFollowLoading(true);

    if (isFollowing) {
      await supabase.from("follows").delete()
        .eq("follower_id", user?.id)
        .eq("following_id", viewingProfile);
      setIsFollowing(false);
      setFollowerCount(c => c - 1);
    } else {
      await supabase.from("follows").insert({
        follower_id:  user?.id,
        following_id: viewingProfile,
      });
      setIsFollowing(true);
      setFollowerCount(c => c + 1);
    }
    setFollowLoading(false);
  }

  // ── Data loaders ───────────────────────────────────────────────
  async function loadMatches() {
    setMatchesLoading(true); setMatchesError("");
    try {
      const matches = await fetchMatchesAPI();
      if (!matches || matches.length === 0) setMatchesError("No upcoming fixtures found.");
      else { setMatches(matches); setMatch(matches[0]); }
    } catch (e) { setMatchesError("Could not load matches. Check your connection."); }
    setMatchesLoading(false);
  }

  async function loadOdds(m) {
    setMarketsLoading(true); setSelectedMarket(null); setMarkets([]); setOddsLive(false); setMarketTab(0);
    try {
      const data = await fetchOddsAPI(m.fixtureId, m.home, m.away);
      setMarkets(data.markets); setOddsLive(data.live || false);
      // Also cache H/D/A into matchOdds map
      const h2h = data.markets?.find(g => g.category === "Match result")?.options || null;
      setMatchOdds(prev => ({ ...prev, [m.fixtureId]: h2h }));
    } catch {}
    setMarketsLoading(false);
  }

  async function loadH2HOddsForDate(dateStr) {
    const dateMatches = matches.filter(m => (m.rawDate || "").startsWith(dateStr)).slice(0, 12);
    if (dateMatches.length === 0) return;
    await Promise.allSettled(
      dateMatches.map(async m => {
        const data = await fetchOddsAPI(m.fixtureId, m.home, m.away).catch(() => null);
        const h2h = data?.markets?.find(g => g.category === "Match result")?.options || null;
        setMatchOdds(prev => ({ ...prev, [m.fixtureId]: h2h }));
      })
    );
  }

  async function loadProfile() {
    if (!user) return;
    const { data } = await supabase.from("profiles").select("*").eq("id", user?.id).single();
    if (data) setProfile(data);
  }

  async function loadFeed() {
    if (!user) return;
    const { data } = await supabase
      .from("picks").select("*, profiles(username, id)")
      .order("created_at", { ascending: false }).limit(20);
    if (data) setFeed(data);
  }

  async function loadCalendarPicks() {
    if (!user) return;
    const since = new Date(Date.now() - 90 * 86400000).toISOString();
    const { data } = await supabase
      .from("picks")
      .select("created_at, result")
      .eq("user_id", user.id)
      .gte("created_at", since)
      .order("created_at", { ascending: false });
    if (!data) return;
    // Group by day
    const dayMap = {};
    data.forEach(p => {
      const d = new Date(p.created_at);
      const key = d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
      if (!dayMap[key]) dayMap[key] = { correct: 0, wrong: 0, pending: 0 };
      if (p.result === "correct") dayMap[key].correct++;
      else if (p.result === "wrong") dayMap[key].wrong++;
      else dayMap[key].pending++;
    });
    // Assign a single status per day
    const status = {};
    Object.entries(dayMap).forEach(([key, c]) => {
      if (c.correct > 0 && c.wrong === 0 && c.pending === 0) status[key] = "correct";
      else if (c.wrong > 0 && c.correct === 0 && c.pending === 0) status[key] = "wrong";
      else if (c.correct > 0 && c.wrong > 0) status[key] = "mixed";
      else status[key] = "pending";
    });
    setCalendarPicks(status);
  }

  async function loadMyPicks() {
    if (!user) return;
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);
    const { data } = await supabase
      .from("picks").select("*").eq("user_id", user?.id)
      .gte("created_at", todayStart.toISOString())
      .order("created_at", { ascending: false });
    if (data) setMyPicks(data);
  }

  async function deletePick(pickId) {
    setDeletingPickId(pickId);
    const { data, error } = await supabase.from("picks").delete()
      .eq("id", pickId).eq("user_id", user?.id).select("id");
    if (error) {
      alert("Couldn't remove prediction: " + error.message);
    } else if (!data || data.length === 0) {
      alert("Remove failed — please check your Supabase RLS policies allow DELETE on picks where user_id = auth.uid()");
    } else {
      await loadMyPicks();
      await loadFeed();
      await loadCalendarPicks();
    }
    setDeletingPickId(null);
  }

  async function updatePickConfidence(pick, newConf) {
    const diff      = getDifficulty(pick.market);
    const cappedWin = calcPointsWinCapped(pick.odds, newConf, diff?.key);
    const finalWin  = Math.round(cappedWin * getStreakMultiplier((profile?.current_streak || 0) + 1));
    const finalLoss = calcPointsLoss(newConf, diff?.multiplier || 1, diff?.key);
    const { data, error } = await supabase.from("picks").update({
      confidence:      newConf,
      points_possible: finalWin,
      points_lost:     finalLoss,
    }).eq("id", pick.id).eq("user_id", user?.id).select("id");
    if (error) {
      alert("Couldn't update prediction: " + error.message);
    } else if (!data || data.length === 0) {
      alert("Update failed — please check your Supabase RLS policies allow UPDATE on picks where user_id = auth.uid()");
    } else {
      setEditingPickId(null);
      await loadMyPicks();
    }
  }

  async function searchUsers(query) {
    if (!query.trim()) { setSearchResults([]); return; }
    setSearchLoading(true);
    const { data } = await supabase
      .from("profiles")
      .select("id, username, weekly_points, total_points")
      .ilike("username", "%" + query + "%")
      .limit(10);
    setSearchResults(data || []);
    setSearchLoading(false);
  }

  async function loadLeaderboard(tab) {
    setLbLoading(true);
    const col = tab === "weekly" ? "weekly_points" : "total_points";
    const { data } = await supabase
      .from("profiles").select("id, username, weekly_points, total_points, current_streak, best_streak")
      .order(col, { ascending: false }).limit(50);
    if (data) {
      const enriched = await Promise.all(data.map(async (p, idx) => {
        const { data: picks } = await supabase
          .from("picks").select("result").eq("user_id", p.id);
        const total    = picks?.length || 0;
        const correct  = picks?.filter(pk => pk.result === "correct").length || 0;
        const accuracy = total > 0 ? Math.round((correct / total) * 100) : null;
        return { ...p, rank: idx + 1, total, correct, accuracy };
      }));
      setLbData(enriched);
    }
    setLbLoading(false);
  }

  async function loadAdminPicks() {
    setAdminLoading(true);
    // Only loads picks from registered users — guest picks are stored in localStorage only and never appear here
    const { data } = await supabase
      .from("picks").select("*, profiles(username)")
      .eq("result", "pending").order("created_at", { ascending: false });
    setAdminPicks(data || []);
    setAdminLoading(false);
  }

  async function resolvePick(pickId, result) {
    setResolvingId(pickId); setAdminMsg({ text: "", ok: true });
    try {
      const res  = await fetch(`${process.env.NEXT_PUBLIC_API_BASE_URL}/api/resolve`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ pickId, result }),
      });
      const data = await res.json();
      if (data.error) { setAdminMsg({ text: `Error: ${data.error}`, ok: false }); }
      else {
        setAdminMsg({ text: result === "correct" ? `+${data.pointsEarned} pts awarded` : `${data.pointsEarned} pts deducted`, ok: true });
        await loadAdminPicks(); await loadProfile(); await loadMyPicks(); await loadFeed();
      }
    } catch { setAdminMsg({ text: "Network error", ok: false }); }
    setResolvingId(null);
  }

  async function handleSettle() {
    if (!settleMatch || homeScore === "" || awayScore === "") return;
    setSettleLoading(true); setSettleResult(null);
    try {
      const res  = await fetch(`${process.env.NEXT_PUBLIC_API_BASE_URL}/api/settle`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ match: settleMatch, homeScore: parseInt(homeScore), awayScore: parseInt(awayScore) }),
      });
      const data = await res.json();
      setSettleResult(data);
      if (!data.error) { await loadAdminPicks(); await loadFeed(); }
    } catch { setSettleResult({ error: "Network error" }); }
    setSettleLoading(false);
  }

  async function loadSimPicks() {
    if (!simMatch) return;
    const { data } = await supabase
      .from("picks").select("*, profiles(username)")
      .eq("match", simMatch).eq("result", "pending");
    setSimPicks(data || []);
    setSimOutput(null);
    setSimLeaderboard(null);
    // Default every pick to "correct"
    const defaults = {};
    (data || []).forEach(p => { defaults[p.id] = "correct"; });
    setPerPickResults(defaults);
  }

  async function handleSimulate() {
    if (!simPicks.length) return;
    setSimLoading(true); setSimOutput(null); setSimLeaderboard(null);
    try {
      const res  = await fetch(`${process.env.NEXT_PUBLIC_API_BASE_URL}/api/simulate`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ picks: simPicks, result: simResult, perPickResults }),
      });
      const data = await res.json();
      setSimOutput(data.simulated);

      // Build simulated leaderboard from current lbData + simulated points
      const { data: profiles } = await supabase
        .from("profiles")
        .select("id, username, total_points, weekly_points, current_streak");

      if (profiles && data.simulated) {
        // Map points delta per user
        const deltaMap = {};
        data.simulated.forEach(r => {
          if (!deltaMap[r.username]) deltaMap[r.username] = 0;
          deltaMap[r.username] += r.points;
        });

        // Build simulated board
        const simBoard = profiles.map((p, idx) => {
          const delta    = deltaMap[p.username] || 0;
          const newTotal = (p.total_points || 0) + delta;
          return { ...p, delta, simTotal: newTotal };
        });

        // Sort by simulated total descending
        simBoard.sort((a, b) => b.simTotal - a.simTotal);

        // Add original rank for comparison
        const origSorted = [...profiles].sort((a, b) => (b.total_points || 0) - (a.total_points || 0));
        const origRankMap = {};
        origSorted.forEach((p, i) => { origRankMap[p.id] = i + 1; });

        const withRanks = simBoard.map((p, i) => ({
          ...p,
          simRank:  i + 1,
          origRank: origRankMap[p.id] || 999,
          rankDelta: origRankMap[p.id] - (i + 1),
        }));

        setSimLeaderboard(withRanks);
      }
    } catch (e) { console.error(e); }
    setSimLoading(false);
  }

  // ── Leagues ───────────────────────────────────────────────────
  async function loadMyLeagues() {
    if (!user) return;
    setLeagueLoading(true);
    const { data } = await supabase
      .from("league_members")
      .select("league_id, leagues(id, name, invite_code, creator_id, created_at)")
      .eq("user_id", user?.id);
    setMyLeagues((data || []).map(d => d.leagues).filter(Boolean));
    setLeagueLoading(false);
  }

  async function loadLeagueMembers(leagueId) {
    setLeagueMembLoad(true);
    const { data } = await supabase
      .from("league_members")
      .select("user_id, joined_at, profiles(id, username, total_points, weekly_points, current_streak)")
      .eq("league_id", leagueId)
      .order("joined_at", { ascending: true });
    const members = (data || []).map(d => d.profiles).filter(Boolean);
    members.sort((a, b) => (b.total_points || 0) - (a.total_points || 0));
    setLeagueMembers(members);
    setLeagueMembLoad(false);
  }

  async function handleCreateLeague() {
    if (profile?.is_anonymous) { requireAccount("league"); return; }
    if (!createName.trim()) { setLeagueMsg({ text: "Enter a league name", ok: false }); return; }
    setLeagueActLoading(true); setLeagueMsg({ text: "", ok: true });
    try {
      // Generate a 6-char invite code directly on the client (no server needed)
      const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
      const code  = Array.from({ length: 6 }, () => chars[Math.floor(Math.random() * chars.length)]).join("");

      const { data: league, error } = await supabase
        .from("leagues")
        .insert({ name: createName.trim(), creator_id: user?.id, invite_code: code })
        .select()
        .single();

      if (error) throw error;

      // Auto-join creator
      const { error: joinErr } = await supabase
        .from("league_members")
        .insert({ league_id: league.id, user_id: user?.id });
      if (joinErr) throw joinErr;

      setLeagueMsg({ text: "League created!", ok: true });
      setCreateName("");
      await loadMyLeagues();
      setLeagueAction("list");
    } catch (err) {
      setLeagueMsg({ text: err.message || "Could not create league. Try again.", ok: false });
    }
    setLeagueActLoading(false);
  }

  async function handleJoinLeague() {
    if (profile?.is_anonymous) { requireAccount("league"); return; }
    if (!joinCode.trim()) { setLeagueMsg({ text: "Enter an invite code", ok: false }); return; }
    setLeagueActLoading(true); setLeagueMsg({ text: "", ok: true });
    try {
      const { data: league, error: leagueErr } = await supabase
        .from("leagues")
        .select("*")
        .eq("invite_code", joinCode.toUpperCase().trim())
        .maybeSingle();

      if (leagueErr) throw leagueErr;
      if (!league) throw new Error("Invalid invite code — league not found");

      const { data: existing } = await supabase
        .from("league_members")
        .select("id")
        .eq("league_id", league.id)
        .eq("user_id", user?.id)
        .maybeSingle();

      if (existing) throw new Error("You are already in this league");

      const { error: joinErr } = await supabase
        .from("league_members")
        .insert({ league_id: league.id, user_id: user?.id });
      if (joinErr) throw joinErr;

      setLeagueMsg({ text: "Joined " + league.name + "!", ok: true });
      setJoinCode("");
      await loadMyLeagues();
      setLeagueAction("list");
    } catch (err) {
      setLeagueMsg({ text: err.message || "Could not join league. Try again.", ok: false });
    }
    setLeagueActLoading(false);
  }

  async function handleLeaveLeague(leagueId) {
    await supabase.from("league_members")
      .delete().eq("league_id", leagueId).eq("user_id", user?.id);
    setLeagueView(null);
    await loadMyLeagues();
  }

  function copyCode(code) {
    navigator.clipboard.writeText(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  async function handleInviteByEmail() {
    if (!inviteEmail.trim()) { setInviteMsg({ text: "Enter an email address", ok: false }); return; }
    setInviteLoading(true); setInviteMsg({ text: "", ok: true });
    const res  = await fetch(`${process.env.NEXT_PUBLIC_API_BASE_URL}/api/invite-league`, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ leagueId: leagueView?.id, inviterUserId: user?.id, email: inviteEmail.trim().toLowerCase() }),
    });
    const data = await res.json();
    if (data.error) { setInviteMsg({ text: data.error, ok: false }); }
    else {
      setInviteMsg({ text: data.username + " added to the league!", ok: true });
      setInviteEmail("");
      loadLeagueMembers(leagueView.id);
    }
    setInviteLoading(false);
  }

  // ── Anonymous Auth (Supabase) ───────────────────────────────────
  async function startGuestMode() {
    if (!guestName.trim()) return;
    setAuthLoading(true); setAuthError("");
    try {
      // Sign in anonymously — creates a real UID in Supabase
      const { data, error } = await supabase.auth.signInAnonymously();
      if (error) throw error;
      if (!data?.user?.id) throw new Error("Sign-in succeeded but no user was returned. Please try again.");

      // Create their profile with is_anonymous flag + display name
      const { error: pe } = await supabase.from("profiles").upsert({
        id:           data.user.id,
        username:     guestName.trim(),
        display_name: guestName.trim(),
        is_anonymous: true,
      }, { onConflict: "id" });
      if (pe) console.error("Profile create error:", pe.message);
      // user state is set by onAuthStateChange automatically
    } catch (err) {
      setAuthError(err.message || "Could not start session. Try again.");
    }
    setAuthLoading(false);
  }

  // Upgrade: link email+password to existing anonymous UID
  // This is the key — same UID, picks and streak preserved
  async function handleUpgrade() {
    if (!email.trim())    { setAuthError("Please enter your email"); return; }
    if (password.length < 6) { setAuthError("Password must be at least 6 characters"); return; }
    setAuthLoading(true); setAuthError("");
    try {
      // Link email+password to existing anonymous account server-side (no confirmation email)
      const res  = await fetch(`${process.env.NEXT_PUBLIC_API_BASE_URL}/api/upgrade`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ userId: user.id, email, password }),
      });
      const data = await res.json();
      if (data.error) throw new Error(data.error);

      await loadProfile();
      setUpgradePrompt(null);
    } catch (err) {
      setAuthError(err.message || "Could not link account. Try again.");
    }
    setAuthLoading(false);
  }

  function requireAccount(reason) {
    setUpgradePrompt(reason);
  }

  // Check if anonymous user's 72-hour trial has expired
  function isTrialExpired() {
    if (!profile?.is_anonymous) return false;
    const created = new Date(user?.created_at || profile?.created_at);
    const hours   = (Date.now() - created.getTime()) / 3600000;
    return hours >= 72;
  }

  // Check if anonymous user should see streak upgrade nudge (3-day streak)
  function shouldNudgeUpgrade() {
    if (!profile?.is_anonymous) return false;
    return (profile?.current_streak || 0) >= 3;
  }

  // ── Auth ───────────────────────────────────────────────────────
  async function handleSignUp() {
    if (!username.trim()) { setAuthError("Please enter a username"); return; }
    if (!email.trim())    { setAuthError("Please enter your email"); return; }
    if (password.length < 6) { setAuthError("Password must be at least 6 characters"); return; }
    setAuthLoading(true); setAuthError("");

    // If already anonymous, upgrade that session instead of creating new account
    if (user && profile?.is_anonymous) {
      setAuthError("");
      await handleUpgrade();
      return;
    }

    // Create account server-side with email pre-confirmed (no confirmation email)
    const signupRes = await fetch(`${process.env.NEXT_PUBLIC_API_BASE_URL}/api/signup`, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password, username }),
    });
    const signupData = await signupRes.json();
    if (signupData.error) { setAuthError(signupData.error); setAuthLoading(false); return; }

    // Sign in immediately — no email confirmation required
    const { error: loginError } = await supabase.auth.signInWithPassword({ email, password });
    if (loginError) { setAuthError(loginError.message); setAuthLoading(false); return; }
    setAuthLoading(false);
  }

  async function handleLogin() {
    setAuthLoading(true); setAuthError("");
    let { error } = await supabase.auth.signInWithPassword({ email, password });

    // If email was never confirmed (old account), auto-confirm via server and retry
    if (error?.message?.toLowerCase().includes("email not confirmed")) {
      const confirmRes = await fetch(`${process.env.NEXT_PUBLIC_API_BASE_URL}/api/confirm-email`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email }),
      });
      const confirmData = await confirmRes.json();
      if (confirmData.error) { setAuthError(confirmData.error); setAuthLoading(false); return; }
      const retry = await supabase.auth.signInWithPassword({ email, password });
      error = retry.error;
    }

    if (error) setAuthError(error.message);
    setAuthLoading(false);
  }

  async function handleLogout() {
    await supabase.auth.signOut();
    setFeed([]); setMyPicks([]); setMatches([]); setMatch(null);
    setProfile(null); setAdminPicks([]); setLbData([]);
    setProfileData(null); setScreen("feed");
  }

  async function submitPick() {
    if (!match || !selectedMarket) return;
    setLoading(true); setError("");
    if (myPicks.length >= 5) { setError("Daily limit reached — 5 predictions per day maximum."); setLoading(false); return; }
    const diff      = getDifficulty(selectedMarket.label);
    const cappedWin = calcPointsWinCapped(selectedMarket.odds, conf, diff.key);
    const finalWin  = Math.round(cappedWin * streakMult);
    const finalLoss = calcPointsLoss(conf, diff.multiplier);

    const { error } = await supabase.from("picks").insert({
      user_id: user?.id, match: match.home + " vs " + match.away,
      market: selectedMarket.label, confidence: conf,
      odds: selectedMarket.odds || null, difficulty: diff.key,
      difficulty_multiplier: diff.multiplier,
      points_possible: finalWin, points_lost: finalLoss, result: "pending",
    });
    if (error) { setError("Failed to save pick."); setLoading(false); return; }
    if (notifyOnPick) await scheduleMatchReminder(match);
    await loadFeed(); await loadMyPicks();
    setLoading(false); setScreen("done");
  }

  function validateAndAdd(opt, matchId, matchLabel, category, currentSlip) {
    // Helper: parse "over X" / "under X" from a label
    function parseOverUnder(label) {
      const lower = label.toLowerCase();
      const m = lower.match(/(over|under)\s+([0-9.]+)/);
      if (!m) return null;
      return { dir: m[1], val: parseFloat(m[2]) };
    }

    // Extract the stat type (goals, corners, cards) from label
    function getStat(label) {
      const lower = label.toLowerCase();
      if (lower.includes("corner")) return "corners";
      if (lower.includes("card")) return "cards";
      if (lower.includes("goal")) return "goals";
      return "goals"; // default for over/under without explicit stat
    }

    const newKey    = opt.key + "_" + matchId;
    const newLabel  = opt.label.toLowerCase();
    const newOU     = parseOverUnder(opt.label);
    const newStat   = newOU ? getStat(opt.label) : null;

    for (const existing of currentSlip) {
      if (existing.key === newKey) return null; // already in slip, will toggle off

      const exLabel = existing.label.toLowerCase();
      const exOU    = parseOverUnder(existing.label);
      const exStat  = exOU ? getStat(existing.label) : null;

      // ── Rule 1: Same match, same market category → auto-replace ──
      // e.g. swapping Home win for Away win
      if (existing.matchId === matchId && existing.category === category) {
        // Mutually exclusive outcomes in same market — replace silently
        const replacedSlip = currentSlip.filter(p => p.key !== existing.key);
        return { action: "replace", slip: replacedSlip };
      }

      // ── Rule 2: Conflicting over/under on same stat + same match ──
      // e.g. Over 2.5 goals AND Under 2.5 goals
      if (existing.matchId === matchId && newOU && exOU && newStat === exStat) {
        if (newOU.dir !== exOU.dir && Math.abs(newOU.val - exOU.val) < 0.1) {
          return { action: "error", msg: "Conflicting selection — can\'t have Over " + newOU.val + " and Under " + exOU.val + " " + newStat };
        }
      }

      // ── Rule 3: Redundant over/under on same stat + same match ──
      // e.g. Under 1.5 cards already in slip, trying to add Under 2.5 cards
      // If under X and adding under Y where Y > X → Y is redundant (X already covers it)
      // If over X and adding over Y where Y < X → Y is redundant (X already covers it)
      if (existing.matchId === matchId && newOU && exOU && newStat === exStat && newOU.dir === exOU.dir) {
        if (newOU.dir === "under" && newOU.val > exOU.val) {
          return { action: "error", msg: "🔄 Already covered — Under " + exOU.val + " " + exStat + " includes Under " + newOU.val };
        }
        if (newOU.dir === "under" && newOU.val < exOU.val) {
          return { action: "error", msg: "🔄 Already covered — Under " + exOU.val + " " + exStat + " includes Under " + newOU.val };
        }
        if (newOU.dir === "over" && newOU.val < exOU.val) {
          return { action: "error", msg: "🔄 Already covered — Over " + exOU.val + " " + exStat + " includes Over " + newOU.val };
        }
        if (newOU.dir === "over" && newOU.val > exOU.val) {
          return { action: "error", msg: "🔄 Already covered — Over " + exOU.val + " " + exStat + " includes Over " + newOU.val };
        }
      }

      // ── Rule 4: BTTS + Not both are mutually exclusive ──
      if (existing.matchId === matchId) {
        if ((exLabel.includes("both score") && newLabel.includes("not both")) ||
            (exLabel.includes("not both")   && newLabel.includes("both score"))) {
          return { action: "error", msg: "Conflicting — Both score and Not both can\'t be in the same slip" };
        }
      }
    }

    return { action: "add" };
  }

  function handleAddToSlip(opt, matchId, matchLabel, category) {
    const slipKey = opt.key + "_" + matchId;
    setSlipError("");

    // Toggling off
    if (betslip.some(p => p.key === slipKey)) {
      setBetslip(bs => bs.filter(p => p.key !== slipKey));
      if (selectedMarket?.key === opt.key) setSelectedMarket(null);
      return;
    }

    const result = validateAndAdd(opt, matchId, matchLabel, category, betslip);
    if (!result) return; // same key, do nothing

    if (result.action === "error") {
      setSlipError(result.msg);
      setTimeout(() => setSlipError(""), 3000);
      return;
    }

    if (result.action === "replace") {
      // Same market, different outcome — swap it out silently like real bookmakers
      setBetslip([...result.slip, { ...opt, key: slipKey, matchLabel, matchId, category }]);
      setSelectedMarket(opt);
      setSlipOpen(false);
      return;
    }

    // Normal add
    setBetslip(bs => [...bs, { ...opt, key: slipKey, matchLabel, matchId, category }]);
    setSelectedMarket(opt);
    setSlipOpen(false);
  }

  async function submitAcca() {
    if (!betslip.length) return;
    setLoading(true); setError("");
    if (myPicks.length >= 5) { setError("Daily limit reached — 5 predictions per day maximum."); setLoading(false); return; }
    const diff = getDifficulty(betslip[0].label);
    const combinedOdds = parseFloat(betslip.reduce((acc, p) => acc * (p.odds || 2.0), 1).toFixed(2));
    const accaBase   = Math.round(50 * Math.log2(combinedOdds + 1) * (conf / 100) * 1.5);
    const accaPoints = Math.min(Math.round(accaBase * streakMult), 400);
    const accaLoss   = Math.round(calcPointsLoss(conf, 1) * betslip.length);
    const label      = betslip.map(p => p.label).join(" + ");
    const matchLabel = betslip.map(p => p.matchLabel).join(" / ");

    const { error } = await supabase.from("picks").insert({
      user_id: user?.id,
      match:   matchLabel,
      market:  label + " (Acca x" + betslip.length + ")",
      confidence: conf,
      odds:    combinedOdds,
      difficulty: diff.key,
      difficulty_multiplier: diff.multiplier,
      points_possible: accaPoints,
      points_lost:     accaLoss,
      result: "pending",
    });
    if (error) { setError("Failed to save acca."); setLoading(false); return; }
    if (notifyOnPick && match) await scheduleMatchReminder(match);
    await loadFeed(); await loadMyPicks();
    setLoading(false); setBetslip([]); setScreen("done");
  }

  // ── Auth / Guest screen ────────────────────────────────────────
  if (!user) {
    return (
      <div style={s.root}>
        <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&display=swap" rel="stylesheet" />
        <div style={{ ...s.screen, justifyContent: "center" }}>

          {/* ── Welcome screen ── */}
          {authScreen === "welcome" && (
            <div style={{ display: "flex", flexDirection: "column", alignItems: "center", padding: "0 28px" }}>
              <div style={{ width: 72, height: 72, borderRadius: 20, background: "linear-gradient(135deg, #6c63ff, #a855f7)", display: "flex", alignItems: "center", justifyContent: "center", marginBottom: 20, boxShadow: "0 8px 32px #6c63ff40" }}>
                <span style={{ fontSize: 32 }}>🎯</span>
              </div>
              <h1 style={{ margin: "0 0 6px", fontSize: 28, fontWeight: 900, color: "#f0eff8", letterSpacing: "-.02em" }}>Predkt</h1>
              <p style={{ margin: "0 0 40px", fontSize: 14, color: "#4a4958", textAlign: "center" }}>Predict football. Prove your knowledge.</p>

              <button onClick={() => setAuthScreen("guest")} style={{ width: "100%", padding: "14px", borderRadius: 12, border: "none", background: "linear-gradient(135deg, #6c63ff, #8a83ff)", color: "#fff", fontSize: 15, fontWeight: 700, cursor: "pointer", marginBottom: 10 }}>
                Play without signing up
              </button>
              <button onClick={() => { setAuthScreen("signup"); setAuthError(""); }} style={{ width: "100%", padding: "14px", borderRadius: 12, border: "0.5px solid #2a2a32", background: "transparent", color: "#f0eff8", fontSize: 15, fontWeight: 600, cursor: "pointer", marginBottom: 10 }}>
                Create account
              </button>
              <button onClick={() => { setAuthScreen("login"); setAuthError(""); }} style={{ background: "none", border: "none", color: "#4a4958", fontSize: 13, cursor: "pointer", padding: "8px 0" }}>
                Already have an account? Log in
              </button>
            </div>
          )}

          {/* ── Guest name entry (anonymous auth) ── */}
          {authScreen === "guest" && (
            <div style={{ padding: "0 28px", width: "100%" }}>
              <button onClick={() => setAuthScreen("welcome")} style={{ background: "none", border: "none", color: "#6c63ff", fontSize: 13, cursor: "pointer", padding: "0 0 20px", fontWeight: 600 }}>← Back</button>
              <h2 style={{ margin: "0 0 6px", fontSize: 22, fontWeight: 800, color: "#f0eff8" }}>Pick your name</h2>
              <p style={{ margin: "0 0 8px", fontSize: 13, color: "#4a4958", lineHeight: 1.5 }}>No email needed. Jump straight in and start predicting.</p>
              <div style={{ background: "#1a1408", border: "0.5px solid #f59e0b44", borderRadius: 10, padding: "10px 12px", marginBottom: 20 }}>
                <p style={{ margin: "0 0 4px", fontSize: 11, fontWeight: 700, color: "#f59e0b" }}>⏱ 72-hour free trial</p>
                <p style={{ margin: 0, fontSize: 11, color: "#4a4958", lineHeight: 1.4 }}>Your picks and streak are real and appear on the leaderboard. After 72 hours, add an email to keep your progress — or lose it forever.</p>
              </div>
              <p style={s.fieldLabel}>Your name</p>
              <input
                type="text"
                placeholder="e.g. SharpKing23"
                value={guestName}
                onChange={e => setGuestName(e.target.value)}
                onKeyDown={e => e.key === "Enter" && startGuestMode()}
                style={{ ...s.input, marginBottom: 8 }}
                autoFocus
              />
              <p style={{ margin: "0 0 20px", fontSize: 11, color: "#3a3a50" }}>This name shows on your predictions and the leaderboard.</p>
              {authError && <p style={{ fontSize: 13, color: "#ef4444", margin: "0 0 12px" }}>{authError}</p>}
              <button onClick={startGuestMode} disabled={!guestName.trim() || authLoading} style={{ width: "100%", padding: "14px", borderRadius: 12, border: "none", background: guestName.trim() ? "linear-gradient(135deg, #6c63ff, #8a83ff)" : "#1e1e28", color: guestName.trim() ? "#fff" : "#3a3a50", fontSize: 15, fontWeight: 700, cursor: "pointer", marginBottom: 12 }}>
                {authLoading ? "Setting up..." : "Start predicting"}
              </button>
              <button onClick={() => { setAuthScreen("signup"); setAuthError(""); }} style={{ width: "100%", padding: "11px", background: "none", border: "none", color: "#4a4958", fontSize: 12, cursor: "pointer" }}>
                Create a full account instead
              </button>
            </div>
          )}

          {/* ── Sign up ── */}
          {authScreen === "signup" && (
            <div style={{ padding: "0 28px", width: "100%" }}>
              <button onClick={() => setAuthScreen("welcome")} style={{ background: "none", border: "none", color: "#6c63ff", fontSize: 13, cursor: "pointer", padding: "0 0 20px", fontWeight: 600 }}>← Back</button>
              <h2 style={{ margin: "0 0 6px", fontSize: 22, fontWeight: 800, color: "#f0eff8" }}>Create account</h2>
              <p style={{ margin: "0 0 24px", fontSize: 13, color: "#4a4958" }}>Join leagues, follow friends, keep your streak forever.</p>
              <p style={s.fieldLabel}>Username</p>
              <input type="text" placeholder="e.g. SharpKing" value={username} onChange={e => setUsername(e.target.value)} style={s.input} />
              <p style={s.fieldLabel}>Email</p>
              <input type="email" placeholder="you@email.com" value={email} onChange={e => setEmail(e.target.value)} style={s.input} autoComplete="email" />
              <p style={s.fieldLabel}>Password</p>
              <input type="password" placeholder="At least 6 characters" value={password} onChange={e => setPassword(e.target.value)} style={s.input} autoComplete="new-password" />
              {authError && <p style={{ fontSize: 13, color: "#ef4444", margin: "0 0 12px" }}>{authError}</p>}
              <button style={{ width: "100%", padding: "14px", borderRadius: 12, border: "none", background: authLoading ? "#1e1e28" : "linear-gradient(135deg, #6c63ff, #8a83ff)", color: authLoading ? "#3a3a50" : "#fff", fontSize: 15, fontWeight: 700, cursor: "pointer", marginBottom: 12 }} onClick={handleSignUp} disabled={authLoading}>
                {authLoading ? "Creating account..." : "Create account"}
              </button>
              <button onClick={() => { setAuthScreen("login"); setAuthError(""); }} style={{ width: "100%", padding: "11px", background: "none", border: "none", color: "#4a4958", fontSize: 12, cursor: "pointer" }}>
                Already have an account? Log in
              </button>
            </div>
          )}

          {/* ── Log in ── */}
          {authScreen === "login" && (
            <div style={{ padding: "0 28px", width: "100%" }}>
              <button onClick={() => setAuthScreen("welcome")} style={{ background: "none", border: "none", color: "#6c63ff", fontSize: 13, cursor: "pointer", padding: "0 0 20px", fontWeight: 600 }}>← Back</button>
              <h2 style={{ margin: "0 0 6px", fontSize: 22, fontWeight: 800, color: "#f0eff8" }}>Welcome back</h2>
              <p style={{ margin: "0 0 24px", fontSize: 13, color: "#4a4958" }}>Log in to see your streak, leagues and leaderboard.</p>
              <p style={s.fieldLabel}>Email</p>
              <input type="email" placeholder="you@email.com" value={email} onChange={e => setEmail(e.target.value)} style={s.input} autoComplete="email" />
              <p style={s.fieldLabel}>Password</p>
              <input type="password" placeholder="••••••••" value={password} onChange={e => setPassword(e.target.value)} style={s.input} autoComplete="current-password" />
              {authError && <p style={{ fontSize: 13, color: "#ef4444", margin: "0 0 12px" }}>{authError}</p>}
              <button style={{ width: "100%", padding: "14px", borderRadius: 12, border: "none", background: authLoading ? "#1e1e28" : "linear-gradient(135deg, #6c63ff, #8a83ff)", color: authLoading ? "#3a3a50" : "#fff", fontSize: 15, fontWeight: 700, cursor: "pointer", marginBottom: 12 }} onClick={handleLogin} disabled={authLoading}>
                {authLoading ? "Logging in..." : "Log in"}
              </button>
              <button onClick={() => { setAuthScreen("signup"); setAuthError(""); }} style={{ width: "100%", padding: "11px", background: "none", border: "none", color: "#4a4958", fontSize: 12, cursor: "pointer" }}>
                Don't have an account? Sign up
              </button>
            </div>
          )}

          {/* ── Upgrade: link email to anonymous account ── */}
          {authScreen === "upgrade" && (
            <div style={{ padding: "0 28px", width: "100%" }}>
              <h2 style={{ margin: "0 0 6px", fontSize: 22, fontWeight: 800, color: "#f0eff8" }}>Lock in your progress</h2>
              <p style={{ margin: "0 0 20px", fontSize: 13, color: "#4a4958", lineHeight: 1.5 }}>Add your email to save your picks, streak and points forever — across any device.</p>
              <div style={{ background: "#0a1a0a", border: "0.5px solid #22c55e30", borderRadius: 10, padding: "10px 12px", marginBottom: 20 }}>
                <p style={{ margin: 0, fontSize: 12, color: "#22c55e" }}>✓ Your {profile?.current_streak || 0}-day streak and all {profilePicks?.length || 0} picks are preserved</p>
              </div>
              <p style={s.fieldLabel}>Email</p>
              <input type="email" placeholder="you@email.com" value={email} onChange={e => setEmail(e.target.value)} style={s.input} autoComplete="email" />
              <p style={s.fieldLabel}>Password</p>
              <input type="password" placeholder="At least 6 characters" value={password} onChange={e => setPassword(e.target.value)} style={s.input} />
              {authError && <p style={{ fontSize: 13, color: "#ef4444", margin: "0 0 12px" }}>{authError}</p>}
              <button onClick={handleUpgrade} disabled={authLoading} style={{ width: "100%", padding: "14px", borderRadius: 12, border: "none", background: authLoading ? "#1e1e28" : "linear-gradient(135deg, #22c55e, #16a34a)", color: authLoading ? "#3a3a50" : "#fff", fontSize: 15, fontWeight: 700, cursor: "pointer", marginBottom: 10 }}>
                {authLoading ? "Saving your account..." : "Save my progress"}
              </button>
              <button onClick={() => setUpgradePrompt(null)} style={{ width: "100%", padding: "11px", background: "none", border: "none", color: "#4a4958", fontSize: 12, cursor: "pointer" }}>
                Not now
              </button>
            </div>
          )}

          {/* ── Email verify confirmation ── */}
          {authScreen === "verify" && (
            <div style={{ padding: "0 28px", width: "100%", textAlign: "center" }}>
              <div style={{ fontSize: 52, marginBottom: 16 }}>📬</div>
              <h2 style={{ margin: "0 0 8px", fontSize: 22, fontWeight: 800, color: "#f0eff8" }}>Check your email</h2>
              <p style={{ margin: "0 0 8px", fontSize: 14, color: "#8b8a99", lineHeight: 1.6 }}>
                We sent a confirmation link to <span style={{ color: "#6c63ff", fontWeight: 600 }}>{email}</span>.
              </p>
              <p style={{ margin: "0 0 32px", fontSize: 13, color: "#4a4958", lineHeight: 1.5 }}>
                Click the link in the email to verify your account and you're in. Check your spam folder if you don't see it.
              </p>
              <button onClick={() => { setAuthScreen("login"); setAuthError(""); }} style={{ width: "100%", padding: "14px", borderRadius: 12, border: "none", background: "#6c63ff", color: "#fff", fontSize: 15, fontWeight: 700, cursor: "pointer", marginBottom: 10 }}>
                Go to log in
              </button>
              <button onClick={handleSignUp} disabled={authLoading} style={{ width: "100%", padding: "11px", background: "none", border: "none", color: "#4a4958", fontSize: 12, cursor: "pointer" }}>
                {authLoading ? "Resending..." : "Resend email"}
              </button>
            </div>
          )}

        </div>
      </div>
    );
  }

  const NAV = [
    { id: "feed",        label: "Feed",    icon: <FeedIcon />    },
    { id: "leaderboard", label: "Board",   icon: <BoardIcon />   },
    { id: "predict",     label: "Predict", icon: <PlusIcon />    },
    { id: "leagues",     label: "Leagues", icon: <LeagueIcon />  },
    { id: "profile",     label: "Profile", icon: <ProfileIcon /> },
  ];

  return (
    <div style={s.root}>
      <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&display=swap" rel="stylesheet" />

      {/* ── Feed ─────────────────────────────────────────── */}
      {screen === "feed" && (
        <div style={s.screen}>
          <div style={s.header}>
            <span style={s.logo}>Predkt</span>
            <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
              {isAdmin && (
                <button onClick={() => setScreen("admin")} style={{ background: "#ef444415", border: "0.5px solid #ef444444", color: "#ef4444", fontSize: 11, fontWeight: 600, padding: "3px 10px", borderRadius: 6, cursor: "pointer" }}>
                  Admin
                </button>
              )}
              <button onClick={handleLogout} style={{ background: "none", border: "none", color: "#4a4958", fontSize: 12, cursor: "pointer" }}>Log out</button>
            </div>
          </div>
          <div style={{ flex: 1, overflowY: "auto", paddingBottom: 16 }}>
            {/* Search */}
            <div style={{ padding: "12px 16px 4px" }}>
              <div style={{ display: "flex", alignItems: "center", gap: 8, background: "#1a1a1f", border: "0.5px solid #2a2a32", borderRadius: 12, padding: "9px 14px" }}>
                <svg width="15" height="15" viewBox="0 0 20 20" fill="none" style={{ flexShrink: 0 }}><circle cx="9" cy="9" r="6" stroke="#4a4958" strokeWidth="1.5"/><path d="M13.5 13.5L17 17" stroke="#4a4958" strokeWidth="1.5" strokeLinecap="round"/></svg>
                <input type="text" placeholder="Search users..." value={searchQuery}
                  onChange={e => {
                    const v = e.target.value;
                    setSearchQuery(v);
                    setShowSearch(v.length > 0);
                    if (searchTimerRef.current) clearTimeout(searchTimerRef.current);
                    if (v.trim()) searchTimerRef.current = setTimeout(() => searchUsers(v), 220);
                    else setSearchResults([]);
                  }}
                  style={{ background: "none", border: "none", outline: "none", color: "#f0eff8", fontSize: 13, flex: 1 }} />
                {searchQuery && (
                  <button onClick={() => { setSearchQuery(""); setSearchResults([]); setShowSearch(false); }} style={{ background: "none", border: "none", color: "#4a4958", cursor: "pointer", padding: 0, fontSize: 18, lineHeight: 1 }}>x</button>
                )}
              </div>
              {showSearch && (
                <div style={{ marginTop: 8, background: "#1a1a1f", border: "0.5px solid #2a2a32", borderRadius: 12, overflow: "hidden" }}>
                  {searchLoading && <p style={{ fontSize: 13, color: "#4a4958", padding: "12px 14px", margin: 0 }}>Searching...</p>}
                  {!searchLoading && searchResults.length === 0 && <p style={{ fontSize: 13, color: "#4a4958", padding: "12px 14px", margin: 0 }}>No users found</p>}
                  {!searchLoading && searchResults.map((u, i) => (
                    <button key={u.id} onClick={() => { openProfile(u.id); setShowSearch(false); setSearchQuery(""); setSearchResults([]); }} style={{ width: "100%", display: "flex", alignItems: "center", gap: 10, padding: "10px 14px", background: "none", border: "none", cursor: "pointer", borderBottom: i < searchResults.length - 1 ? "0.5px solid #2a2a32" : "none", textAlign: "left" }}>
                      <div style={{ width: 32, height: 32, borderRadius: "50%", background: "#6c63ff22", border: "0.5px solid #6c63ff44", color: "#8a83ff", fontSize: 12, fontWeight: 600, display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
                        {u.username ? u.username[0].toUpperCase() : "?"}
                      </div>
                      <div style={{ flex: 1 }}>
                        <p style={{ margin: 0, fontSize: 13, fontWeight: 600, color: "#f0eff8" }}>{u.username}</p>
                        <p style={{ margin: 0, fontSize: 11, color: "#4a4958" }}>{u.total_points ?? 0} total pts</p>
                      </div>
                      <svg width="14" height="14" viewBox="0 0 20 20" fill="none"><path d="M7 5l5 5-5 5" stroke="#4a4958" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/></svg>
                    </button>
                  ))}
                </div>
              )}
            </div>

            {profile && (
              <div style={{ padding: "12px 16px 0" }}>
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8, marginBottom: 8 }}>
                  <div style={s.statCard}><p style={{ ...s.statLabel, color: "#a09fb8" }}>Weekly pts</p><p style={{ ...s.statVal, color: "#8a83ff" }}>{profile.weekly_points ?? 0}</p></div>
                  <div style={s.statCard}><p style={{ ...s.statLabel, color: "#a09fb8" }}>Total pts</p><p style={{ ...s.statVal, color: "#e8e7f4" }}>{profile.total_points ?? 0}</p></div>
                </div>
                {/* Daily streak banner */}
                {(profile.daily_streak || 0) >= 1 && (
                  <div style={{ background: "#6c63ff15", border: "0.5px solid #6c63ff44", borderRadius: 10, padding: "10px 14px", display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}>
                    <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                      <span style={{ fontSize: 20 }}>{(profile.daily_streak || 0) >= 7 ? "🔥" : (profile.daily_streak || 0) >= 3 ? "⚡" : "📅"}</span>
                      <div>
                        <p style={{ margin: 0, fontSize: 13, fontWeight: 600, color: "#8a83ff" }}>{profile.daily_streak} day streak</p>
                        <p style={{ margin: 0, fontSize: 11, color: "#4a4958" }}>Pick every day to keep it going</p>
                      </div>
                    </div>
                    <div style={{ textAlign: "right" }}>
                      <p style={{ margin: 0, fontSize: 13, fontWeight: 700, color: "#8a83ff" }}>Best: {profile.best_daily_streak ?? 0}</p>
                    </div>
                  </div>
                )}
                {profile.current_streak >= 1 && (() => {
                  const sl = getStreakLabel(profile.current_streak);
                  const mult = getStreakMultiplier(profile.current_streak + 1);
                  return (
                    <div style={{ background: sl.color + "15", border: "0.5px solid " + sl.color + "44", borderRadius: 10, padding: "10px 14px", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                        <span style={{ fontSize: 20 }}>{profile.current_streak >= 5 ? "🔥" : profile.current_streak >= 3 ? "⚡" : "✓"}</span>
                        <div>
                          <p style={{ margin: 0, fontSize: 13, fontWeight: 600, color: sl.color }}>{profile.current_streak} correct in a row</p>
                          <p style={{ margin: 0, fontSize: 11, color: "#4a4958" }}>Best: {profile.best_streak ?? 0}</p>
                        </div>
                      </div>
                      <div style={{ textAlign: "right" }}>
                        <p style={{ margin: 0, fontSize: 16, fontWeight: 700, color: sl.color }}>{mult}x</p>
                        <p style={{ margin: 0, fontSize: 11, color: "#4a4958" }}>multiplier</p>
                      </div>
                    </div>
                  );
                })()}
              </div>
            )}
            <section style={s.section}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 10 }}>
                <p style={{ ...s.sectionLabel, margin: 0, color: "#c8c7d8" }}>Today's picks</p>
                <span style={{ fontSize: 11, color: "#8b8a99", fontWeight: 500 }}>
                  {new Date().toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" })}
                </span>
              </div>
              {(() => {
                // All users (including anonymous) use Supabase picks
                const displayPicks = myPicks;

                if (displayPicks.length === 0) return (
                  <div style={{ background: "#1a1a1f", border: "0.5px solid #2a2a32", borderRadius: 12, padding: "16px 14px", textAlign: "center" }}>
                    <p style={{ fontSize: 22, margin: "0 0 6px" }}>🎯</p>
                    <p style={{ fontSize: 13, fontWeight: 600, color: "#f0eff8", margin: "0 0 4px" }}>No predictions yet today</p>
                    <p style={{ fontSize: 12, color: "#4a4958", margin: 0 }}>Head to Predict to make your first prediction</p>
                  </div>
                );

                return displayPicks.map((p, i) => {
                  const [pickHome, pickAway] = (p.match || "").split(" vs ");
                  const pickLm = findLiveMatch(liveMatches, pickHome, pickAway, null);
                  const isPickLive = pickLm?.isLive || false;
                  const isPickFinished = pickLm?.isFinished || false;
                  return (
                  <div key={i} style={{ ...s.card, ...(isPickLive ? { background: "#0d1a10", border: "0.5px solid #22c55e55" } : isPickFinished ? { background: "#13131c", border: "0.5px solid #2a2a3a" } : {}) }}>
                    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
                      <div style={{ flex: 1 }}>
                        <div style={{ display: "flex", alignItems: "center", gap: 6, marginBottom: 3 }}>
                          <p style={s.cardTitle}>{p.market}</p>
                          {isPickLive && <span style={{ fontSize: 9, fontWeight: 800, padding: "1px 5px", borderRadius: 4, background: "#22c55e", color: "#000" }}>LIVE</span>}
                          {isPickFinished && !isPickLive && <span style={{ fontSize: 9, fontWeight: 800, padding: "1px 5px", borderRadius: 4, background: "#2a2a3a", color: "#8b8a99" }}>FT</span>}
                          {p.difficulty && <DiffBadge d={p.difficulty} />}
                          {p.streak_multiplier > 1 && <span style={{ fontSize: 10, fontWeight: 600, padding: "1px 5px", borderRadius: 99, background: "#ef444420", color: "#ef4444" }}>{p.streak_multiplier}x</span>}
                        </div>
                        <p style={s.cardSub}>{p.match}</p>
                        {isPickLive && pickLm && (
                          <p style={{ fontSize: 12, fontWeight: 700, color: "#22c55e", marginTop: 2 }}>
                            {pickLm.homeGoals} – {pickLm.awayGoals}
                            <span style={{ fontSize: 10, fontWeight: 600, color: "#4caf70", marginLeft: 6 }}>
                              {pickLm.status === "HT" ? "Half Time" : `${pickLm.elapsed ?? 0}'`}
                            </span>
                          </p>
                        )}
                        {isPickFinished && !isPickLive && pickLm && (
                          <p style={{ fontSize: 12, fontWeight: 700, color: "#8b8a99", marginTop: 2 }}>
                            FT: {pickLm.homeGoals} – {pickLm.awayGoals}
                          </p>
                        )}
                        <p style={{ fontSize: 11, color: "#4a4958", marginTop: 3 }}>
                          {p.confidence}% conf{p.odds ? " · " + p.odds + " odds" : ""}
                          {p.created_at && " · " + new Date(p.created_at).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" })}
                        </p>
                      </div>
                      <div style={{ textAlign: "right", flexShrink: 0, marginLeft: 8 }}>
                        <ResultBadge result={p.result} />
                        {p.result === "pending"  && p.points_possible != null && <p style={{ fontSize: 11, color: "#22c55e", marginTop: 3 }}>+{p.points_possible} possible</p>}
                        {p.result === "correct"  && p.points_earned != null   && <p style={{ fontSize: 12, fontWeight: 700, color: "#22c55e", marginTop: 3 }}>+{p.points_earned} pts</p>}
                        {p.result === "wrong"    && p.points_earned != null   && <p style={{ fontSize: 12, fontWeight: 700, color: "#ef4444", marginTop: 3 }}>{p.points_earned} pts</p>}
                      </div>
                    </div>
                    {/* Edit/delete row — pending only */}
                    {p.result === "pending" && (() => {
                      return (
                        <div style={{ marginTop: 8, paddingTop: 8, borderTop: isPickLive ? "0.5px solid #22c55e33" : isPickFinished ? "0.5px solid #2a2a3a" : "0.5px solid #1e1e2a" }}>
                          {isPickFinished ? (
                            <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                              <span style={{ fontSize: 11, color: "#4a4958" }}>Match finished — result pending</span>
                            </div>
                          ) : isPickLive ? (
                            <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                              <span style={{ fontSize: 11, color: "#4caf70" }}>Prediction locked — match in progress</span>
                            </div>
                          ) : editingPickId === p.id ? (
                            <div>
                              <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 4 }}>
                                <span style={{ fontSize: 10, color: "#4a4958", textTransform: "uppercase", fontWeight: 700 }}>Confidence</span>
                                <span style={{ fontSize: 12, fontWeight: 700, color: "#6c63ff" }}>{editPickConf}%</span>
                              </div>
                              <input type="range" min={10} max={90} step={10} value={editPickConf}
                                onChange={e => setEditPickConf(Number(e.target.value))}
                                style={{ width: "100%", accentColor: "#6c63ff", marginBottom: 8 }} />
                              <div style={{ display: "flex", gap: 6 }}>
                                <button onClick={() => setEditingPickId(null)} style={{ flex: 1, padding: "6px", borderRadius: 8, border: "0.5px solid #2a2a32", background: "transparent", color: "#8b8a99", fontSize: 11, cursor: "pointer" }}>Cancel</button>
                                <button onClick={() => updatePickConfidence(p, editPickConf)} style={{ flex: 2, padding: "6px", borderRadius: 8, border: "none", background: "#6c63ff", color: "#fff", fontSize: 11, fontWeight: 600, cursor: "pointer" }}>Save</button>
                              </div>
                            </div>
                          ) : (
                            <div style={{ display: "flex", gap: 6 }}>
                              <button onClick={() => { setEditingPickId(p.id); setEditPickConf(p.confidence || 70); }}
                                style={{ flex: 1, padding: "5px", borderRadius: 6, border: "0.5px solid #2a2a32", background: "transparent", color: "#8a83ff", fontSize: 11, cursor: "pointer" }}>
                                Edit confidence
                              </button>
                              <button onClick={() => deletePick(p.id)} disabled={deletingPickId === p.id}
                                style={{ padding: "5px 10px", borderRadius: 6, border: "0.5px solid #ef444444", background: "#ef444415", color: "#ef4444", fontSize: 11, cursor: "pointer", opacity: deletingPickId === p.id ? 0.5 : 1 }}>
                                {deletingPickId === p.id ? "..." : "Remove"}
                              </button>
                            </div>
                          )}
                        </div>
                      );
                    })()}
                  </div>
                  );
                });
              })()}
            </section>
            <section style={s.section}>
              <p style={{ ...s.sectionLabel, color: "#c8c7d8" }}>Community picks</p>
              {profile?.is_anonymous && (
                <div style={{ background: "#6c63ff12", border: "0.5px solid #6c63ff30", borderRadius: 10, padding: "10px 12px", marginBottom: 10, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                  <p style={{ margin: 0, fontSize: 12, color: "#8a83ff" }}>👻 You're in trial mode — add email to appear permanently</p>
                  <button onClick={() => { setEmail(""); setPassword(""); setAuthScreen("upgrade"); }} style={{ background: "#6c63ff", border: "none", color: "#fff", fontSize: 11, fontWeight: 700, padding: "4px 9px", borderRadius: 6, cursor: "pointer" }}>Save</button>
                </div>
              )}
              {feed.length === 0
                ? <p style={{ fontSize: 13, color: "#4a4958", padding: "8px 0" }}>No picks yet — be the first!</p>
                : feed.map((p, i) => (
                  <div key={i} style={s.card}>
                    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
                      <div style={{ flex: 1 }}>
                        <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 4 }}>
                          <button onClick={() => openProfile(p.profiles?.id)} style={{ display: "flex", alignItems: "center", gap: 8, background: "none", border: "none", cursor: "pointer", padding: 0 }}>
                            <div style={s.avatar}>{p.profiles?.username?.[0] ?? "?"}</div>
                            <span style={{ ...s.userName, textDecoration: "underline", textDecorationColor: "#2a2a32" }}>{p.profiles?.username ?? "Unknown"}</span>
                          </button>
                          {p.difficulty && <DiffBadge d={p.difficulty} />}
                          {p.streak_multiplier > 1 && <span style={{ fontSize: 10, fontWeight: 600, padding: "1px 6px", borderRadius: 99, background: "#ef444420", color: "#ef4444" }}>{p.streak_multiplier}x</span>}
                        </div>
                        <p style={s.cardTitle}>{p.market}</p>
                        <MatchWithCrests matchStr={p.match} matches={matches} />
                      </div>
                      <div style={{ textAlign: "right", flexShrink: 0, marginLeft: 8 }}>
                        <span style={s.confBadge}>{p.confidence}%</span>
                        <ResultBadge result={p.result} />
                      </div>
                    </div>
                  </div>
                ))
              }
            </section>
          </div>
          <BottomNav screen={screen} setScreen={id => { if (id === "profile") { setViewingProfile(null); } setScreen(id); }} nav={NAV} />
        </div>
      )}

      {/* ── Profile ──────────────────────────────────────── */}
      {/* Guest profile */}
      {screen === "profile" && user && profile?.is_anonymous && (
        <div style={s.screen}>
          <div style={s.header}>
            <button style={s.back} onClick={() => setScreen("feed")}>← Back</button>
            <span style={s.logo}>My profile</span>
          </div>
          <div style={s.body}>
            <div style={{ textAlign: "center", paddingBottom: 24 }}>
              <div style={{ width: 60, height: 60, borderRadius: "50%", background: "#6c63ff", display: "flex", alignItems: "center", justifyContent: "center", margin: "0 auto 12px", fontSize: 24, fontWeight: 800, color: "#fff" }}>
                {(profile?.username?.[0] || "?").toUpperCase()}
              </div>
              <p style={{ margin: "0 0 4px", fontSize: 18, fontWeight: 700, color: "#f0eff8" }}>{profile?.username}</p>
              <span style={{ fontSize: 11, background: "#6c63ff20", color: "#8a83ff", padding: "2px 10px", borderRadius: 99, fontWeight: 600 }}>Guest player</span>
              <p style={{ margin: "10px 0 0", fontSize: 12, color: "#4a4958" }}>{profilePicks?.length || 0} predictions made · Trial account</p>
            </div>
            <div style={{ background: "#1a1a1f", borderRadius: 14, padding: "16px", border: "0.5px solid #2a2a32", marginBottom: 16 }}>
              <p style={{ margin: "0 0 4px", fontSize: 14, fontWeight: 700, color: "#f0eff8" }}>Save your progress</p>
              <p style={{ margin: "0 0 16px", fontSize: 12, color: "#8b8a99", lineHeight: 1.5 }}>Create a free account to keep your streak, appear on the leaderboard and join friend leagues.</p>
              <button onClick={() => { setEmail(""); setPassword(""); setAuthScreen("upgrade"); setUpgradePrompt(null); }} style={{ width: "100%", padding: "13px", borderRadius: 10, border: "none", background: "linear-gradient(135deg, #22c55e, #16a34a)", color: "#fff", fontSize: 14, fontWeight: 700, cursor: "pointer" }}>
                Save my progress — add email
              </button>
            </div>
            {profilePicks?.length > 0 && (
              <>
                <p style={s.sectionLabel}>Recent predictions</p>
                {profilePicks.slice(0, 5).map((p, i) => (
                  <div key={i} style={s.card}>
                    <p style={s.cardTitle}>{p.market}</p>
                    <p style={s.cardSub}>{p.match}</p>
                    <p style={{ fontSize: 11, color: "#4a4958" }}>{p.confidence}% confidence · +{p.points_possible} pts possible</p>
                  </div>
                ))}
              </>
            )}
          </div>
          <BottomNav screen={screen} setScreen={id => setScreen(id)} nav={NAV} />
        </div>
      )}

      {screen === "profile" && user && !profile?.is_anonymous && (
        <div style={s.screen}>
          {/* Teal/green header for profile */}
          <div style={s.header}>
            {viewingProfile && viewingProfile !== user?.id
              ? <button style={{ ...s.back, color: "#6c63ff" }} onClick={() => setScreen("feed")}>← Back</button>
              : <span style={{ ...s.logo, color: "#f0eff8" }}>Profile</span>
            }
            {viewingProfile && viewingProfile !== user?.id
              ? <span style={s.logo}>{profileData?.username ?? ""}</span>
              : <button onClick={handleLogout} style={{ background: "none", border: "none", color: "#4a4958", fontSize: 12, cursor: "pointer" }}>Log out</button>
            }
          </div>

          <div style={{ flex: 1, overflowY: "auto", paddingBottom: 16 }}>
            {profileLoading && <p style={{ fontSize: 13, color: "#4a4958", padding: "20px 16px" }}>Loading...</p>}

            {!profileLoading && profileData && (
              <>
                {/* Profile header */}
                <div style={{ padding: "20px 16px 0", textAlign: "center" }}>
                  {/* Avatar */}
                  <div style={{ width: 64, height: 64, borderRadius: "50%", background: "#6c63ff22", border: "2px solid #6c63ff44", color: "#8a83ff", fontSize: 24, fontWeight: 700, display: "flex", alignItems: "center", justifyContent: "center", margin: "0 auto 12px" }}>
                    {profileData.username?.[0]?.toUpperCase() ?? "?"}
                  </div>

                  {/* Username + edit mode */}
                  {editMode ? (
                    <div style={{ marginBottom: 8, width: "100%", maxWidth: 260, margin: "0 auto 8px" }}>
                      <p style={{ fontSize: 10, color: "#4a4958", textTransform: "uppercase", letterSpacing: ".06em", fontWeight: 600, margin: "0 0 4px", textAlign: "left" }}>Username</p>
                      <input type="text" value={editUsername} onChange={e => setEditUsername(e.target.value)} style={{ ...s.input, fontSize: 15, fontWeight: 600, marginBottom: 10 }} autoFocus />
                      {/* Fav teams — multi-select chips */}
                      <p style={{ fontSize: 10, color: "#4a4958", textTransform: "uppercase", letterSpacing: ".06em", fontWeight: 600, margin: "0 0 4px", textAlign: "left" }}>Favourite teams <span style={{ color: "#2a2a32" }}>(up to 5)</span></p>
                      {editFavTeamsList.length > 0 && (
                        <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginBottom: 8 }}>
                          {editFavTeamsList.map((t, i) => (
                            <span key={i} style={{ display: "flex", alignItems: "center", gap: 4, background: "#6c63ff20", border: "0.5px solid #6c63ff44", borderRadius: 99, padding: "3px 8px", fontSize: 11, color: "#8a83ff", fontWeight: 600 }}>
                              ⚽ {t}
                              <button onMouseDown={() => setEditFavTeamsList(lst => lst.filter((_, j) => j !== i))} style={{ background: "none", border: "none", color: "#6c63ff", fontSize: 13, cursor: "pointer", padding: "0 0 0 2px", lineHeight: 1 }}>×</button>
                            </span>
                          ))}
                        </div>
                      )}
                      {editFavTeamsList.length < 5 && (
                        <div style={{ position: "relative", marginBottom: 10 }}>
                          <input type="text" placeholder="Add a team..." value={editFavTeam}
                            onChange={e => {
                              const v = e.target.value;
                              setEditFavTeam(v);
                              if (v.length > 0) {
                                const sugg = allTeamNames.filter(t => t.toLowerCase().includes(v.toLowerCase()) && !editFavTeamsList.includes(t));
                                setTeamSuggestions(sugg.slice(0, 6));
                                setShowTeamDrop(sugg.length > 0);
                              } else {
                                setShowTeamDrop(false);
                                setTeamSuggestions([]);
                              }
                            }}
                            onBlur={() => setTimeout(() => setShowTeamDrop(false), 150)}
                            style={{ ...s.input, marginBottom: 0 }} />
                          {showTeamDrop && (
                            <div style={{ position: "absolute", top: "100%", left: 0, right: 0, background: "#1a1a1f", border: "0.5px solid #6c63ff44", borderRadius: 10, overflow: "hidden", zIndex: 10, marginTop: 4, boxShadow: "0 8px 24px #00000060" }}>
                              {teamSuggestions.map((t, i) => (
                                <button key={i} onMouseDown={() => { setEditFavTeamsList(lst => [...lst, t]); setEditFavTeam(""); setShowTeamDrop(false); }} style={{ width: "100%", padding: "9px 14px", background: "none", border: "none", textAlign: "left", color: "#f0eff8", fontSize: 13, cursor: "pointer", borderBottom: i < teamSuggestions.length - 1 ? "0.5px solid #2a2a32" : "none" }}>
                                  {t}
                                </button>
                              ))}
                            </div>
                          )}
                        </div>
                      )}

                      {/* Fav leagues — multi-select chips */}
                      <p style={{ fontSize: 10, color: "#4a4958", textTransform: "uppercase", letterSpacing: ".06em", fontWeight: 600, margin: "0 0 4px", textAlign: "left" }}>Favourite leagues <span style={{ color: "#2a2a32" }}>(up to 5)</span></p>
                      {editFavLeaguesList.length > 0 && (
                        <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginBottom: 8 }}>
                          {editFavLeaguesList.map((l, i) => (
                            <span key={i} style={{ display: "flex", alignItems: "center", gap: 4, background: "#f59e0b20", border: "0.5px solid #f59e0b44", borderRadius: 99, padding: "3px 8px", fontSize: 11, color: "#f59e0b", fontWeight: 600 }}>
                              🏆 {l}
                              <button onMouseDown={() => setEditFavLeaguesList(lst => lst.filter((_, j) => j !== i))} style={{ background: "none", border: "none", color: "#f59e0b", fontSize: 13, cursor: "pointer", padding: "0 0 0 2px", lineHeight: 1 }}>×</button>
                            </span>
                          ))}
                        </div>
                      )}
                      {editFavLeaguesList.length < 5 && (
                        <div style={{ position: "relative", marginBottom: 10 }}>
                          <input type="text" placeholder="Add a league..." value={editFavLeague}
                            onChange={e => {
                              const v = e.target.value;
                              setEditFavLeague(v);
                              if (v.length > 0) {
                                const sugg = allLeagueNames.filter(l => l.toLowerCase().includes(v.toLowerCase()) && !editFavLeaguesList.includes(l));
                                setLeagueSuggestions(sugg.slice(0, 6));
                                setShowLeagueDrop(sugg.length > 0);
                              } else {
                                setShowLeagueDrop(false);
                                setLeagueSuggestions([]);
                              }
                            }}
                            onBlur={() => setTimeout(() => setShowLeagueDrop(false), 150)}
                            style={{ ...s.input, marginBottom: 0 }} />
                          {showLeagueDrop && (
                            <div style={{ position: "absolute", top: "100%", left: 0, right: 0, background: "#1a1a1f", border: "0.5px solid #f59e0b44", borderRadius: 10, overflow: "hidden", zIndex: 10, marginTop: 4, boxShadow: "0 8px 24px #00000060" }}>
                              {leagueSuggestions.map((l, i) => (
                                <button key={i} onMouseDown={() => { setEditFavLeaguesList(lst => [...lst, l]); setEditFavLeague(""); setShowLeagueDrop(false); }} style={{ width: "100%", padding: "9px 14px", background: "none", border: "none", textAlign: "left", color: "#f0eff8", fontSize: 13, cursor: "pointer", borderBottom: i < leagueSuggestions.length - 1 ? "0.5px solid #2a2a32" : "none" }}>
                                  {l}
                                </button>
                              ))}
                            </div>
                          )}
                        </div>
                      )}
                      {editError && <p style={{ fontSize: 12, color: "#ef4444", margin: "0 0 8px" }}>{editError}</p>}
                      <div style={{ display: "flex", gap: 8, justifyContent: "center" }}>
                        <button onClick={() => { setEditMode(false); setEditError(""); }} style={{ padding: "7px 18px", borderRadius: 8, border: "0.5px solid #2a2a32", background: "transparent", color: "#8b8a99", fontSize: 12, cursor: "pointer" }}>Cancel</button>
                        <button onClick={handleSaveProfile} disabled={editSaving} style={{ padding: "7px 18px", borderRadius: 8, border: "none", background: "#6c63ff", color: "#fff", fontSize: 12, fontWeight: 600, cursor: "pointer", opacity: editSaving ? 0.6 : 1 }}>{editSaving ? "Saving..." : "Save"}</button>
                      </div>
                    </div>
                  ) : (
                    <div>
                      <p style={{ fontSize: 18, fontWeight: 700, color: "#f0eff8", margin: "0 0 4px" }}>{profileData.username}</p>
                      <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 6, marginBottom: 4, flexWrap: "wrap" }}>
                        {profileData.role === "admin" && (
                          <span style={{ fontSize: 11, background: "#ef444420", color: "#ef4444", padding: "2px 8px", borderRadius: 4, fontWeight: 600 }}>Admin</span>
                        )}
                        {(profileData.favourite_team || "").split("|").map(t => t.trim()).filter(Boolean).map((t, i) => (
                          <span key={i} style={{ fontSize: 11, background: "#6c63ff20", color: "#8a83ff", padding: "2px 8px", borderRadius: 4, fontWeight: 500 }}>⚽ {t}</span>
                        ))}
                        {(profileData.favourite_league || "").split("|").map(l => l.trim()).filter(Boolean).map((l, i) => (
                          <span key={i} style={{ fontSize: 11, background: "#f59e0b20", color: "#f59e0b", padding: "2px 8px", borderRadius: 4, fontWeight: 500 }}>🏆 {l}</span>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Joined date */}
                  {profileData.created_at && (
                    <p style={{ fontSize: 11, color: "#4a4958", margin: "0 0 10px" }}>
                      Joined {new Date(profileData.created_at).toLocaleDateString("en-GB", { month: "long", year: "numeric" })}
                    </p>
                  )}

                  {/* Edit profile button — own profile only */}
                  {(!viewingProfile || viewingProfile === user?.id) && !editMode && (
                    <button onClick={() => { setEditUsername(profileData.username || ""); setEditFavTeamsList((profileData.favourite_team || "").split("|").map(t => t.trim()).filter(Boolean)); setEditFavTeam(""); setEditFavLeaguesList((profileData.favourite_league || "").split("|").map(l => l.trim()).filter(Boolean)); setEditFavLeague(""); setEditMode(true); setEditError(""); if (matches.length === 0) loadMatches(); }} style={{ marginBottom: 8, padding: "6px 18px", borderRadius: 99, border: "0.5px solid #2a2a32", background: "transparent", color: "#8b8a99", fontSize: 12, cursor: "pointer" }}>
                      Edit profile
                    </button>
                  )}

                  {/* Follow button — other users only */}
                  {viewingProfile && viewingProfile !== user?.id && (
                    <button onClick={handleFollow} disabled={followLoading} style={{
                      marginTop: 4, padding: "8px 24px", borderRadius: 99,
                      border: isFollowing ? "0.5px solid #6c63ff" : "none",
                      background: isFollowing ? "transparent" : "#6c63ff",
                      color: isFollowing ? "#8a83ff" : "#fff",
                      fontSize: 13, fontWeight: 600, cursor: "pointer",
                      opacity: followLoading ? 0.6 : 1,
                    }}>
                      {followLoading ? "..." : isFollowing ? "Following" : "Follow"}
                    </button>
                  )}
                </div>

                {/* Followers / Following / Picks */}
                {/* <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8, padding: "16px 16px 0" }}>
                  <div style={{ ...s.statCard, textAlign: "center" }}>
                    <p style={{ ...s.statVal, fontSize: 18 }}>{followerCount}</p>
                    <p style={{ ...s.statLabel, margin: 0 }}>Followers</p>
                  </div>
                  <div style={{ ...s.statCard, textAlign: "center" }}>
                    <p style={{ ...s.statVal, fontSize: 18 }}>{followingCount}</p>
                    <p style={{ ...s.statLabel, margin: 0 }}>Following</p>
                  </div>
                  <div style={{ ...s.statCard, textAlign: "center" }}>
                    <p style={{ ...s.statVal, fontSize: 18 }}>{profilePicks.length}</p>
                    <p style={{ ...s.statLabel, margin: 0 }}>Picks</p>
                  </div>
                </div> */}

                {/* Points — kept original colours */}
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8, padding: "12px 16px 0" }}>
                  <div style={{ ...s.statCard }}>
                    <p style={{ fontSize: 11, color: "#4a4958", margin: "0 0 4px", textTransform: "uppercase", letterSpacing: ".05em" }}>Weekly pts</p>
                    <p style={{ fontSize: 20, fontWeight: 700, margin: 0, color: "#6c63ff" }}>{profileData.weekly_points ?? 0}</p>
                  </div>
                  <div style={{ ...s.statCard }}>
                    <p style={{ fontSize: 11, color: "#4a4958", margin: "0 0 4px", textTransform: "uppercase", letterSpacing: ".05em" }}>Total pts</p>
                    <p style={{ fontSize: 20, fontWeight: 700, margin: 0, color: "#f0eff8" }}>{profileData.total_points ?? 0}</p>
                  </div>
                </div>

                {/* Win streak — kept original colours */}
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8, padding: "8px 16px 0" }}>
                  <div style={{ ...s.statCard }}>
                    <p style={{ fontSize: 11, color: "#4a4958", margin: "0 0 4px", textTransform: "uppercase", letterSpacing: ".05em" }}>Win streak</p>
                    <p style={{ fontSize: 20, fontWeight: 700, margin: 0, color: (profileData.current_streak || 0) >= 3 ? "#f59e0b" : "#f0eff8" }}>{profileData.current_streak ?? 0}</p>
                  </div>
                  <div style={{ ...s.statCard }}>
                    <p style={{ fontSize: 11, color: "#4a4958", margin: "0 0 4px", textTransform: "uppercase", letterSpacing: ".05em" }}>Best streak</p>
                    <p style={{ fontSize: 20, fontWeight: 700, margin: 0, color: "#f0eff8" }}>{profileData.best_streak ?? 0}</p>
                  </div>
                </div>

                {/* Daily streak */}
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8, padding: "8px 16px 0" }}>
                  <div style={{ background: "#1a1a1f", border: (profileData.daily_streak || 0) >= 1 ? "0.5px solid #6c63ff44" : "0.5px solid #2a2a32", borderRadius: 10, padding: "10px 12px" }}>
                    <p style={{ fontSize: 11, color: "#4a4958", margin: "0 0 4px", textTransform: "uppercase", letterSpacing: ".05em" }}>Daily streak</p>
                    <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                      <p style={{ fontSize: 20, fontWeight: 700, margin: 0, color: (profileData.daily_streak || 0) >= 7 ? "#ef4444" : (profileData.daily_streak || 0) >= 3 ? "#f59e0b" : "#6c63ff" }}>{profileData.daily_streak ?? 0}</p>
                      {(profileData.daily_streak || 0) >= 7 && <span style={{ fontSize: 16 }}>🔥</span>}
                      {(profileData.daily_streak || 0) >= 3 && (profileData.daily_streak || 0) < 7 && <span style={{ fontSize: 16 }}>⚡</span>}
                    </div>
                  </div>
                  <div style={{ ...s.statCard }}>
                    <p style={{ fontSize: 11, color: "#4a4958", margin: "0 0 4px", textTransform: "uppercase", letterSpacing: ".05em" }}>Best daily</p>
                    <p style={{ fontSize: 20, fontWeight: 700, margin: 0, color: "#f0eff8" }}>{profileData.best_daily_streak ?? 0}</p>
                  </div>
                </div>

                {/* Daily streak progress */}
                {(profileData.daily_streak || 0) >= 1 && (
                  <div style={{ padding: "8px 16px 0" }}>
                    <div style={{ ...s.statCard }}>
                      <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 8 }}>
                        <p style={{ fontSize: 11, color: "#4a4958", margin: 0, textTransform: "uppercase", letterSpacing: ".05em" }}>Daily progress</p>
                        <p style={{ fontSize: 11, color: "#4a4958", margin: 0 }}>{profileData.daily_streak} / 7 days</p>
                      </div>
                      <div style={{ background: "#2a2a32", borderRadius: 4, height: 6, overflow: "hidden" }}>
                        <div style={{ width: Math.min((profileData.daily_streak / 7) * 100, 100) + "%", height: "100%", background: (profileData.daily_streak || 0) >= 7 ? "#ef4444" : "#6c63ff", borderRadius: 4, transition: "width .3s" }} />
                      </div>
                      <p style={{ fontSize: 11, color: "#4a4958", marginTop: 6, textAlign: "center" }}>
                        {(profileData.daily_streak || 0) >= 7 ? "Max streak reached!" : (7 - (profileData.daily_streak || 0)) + " more day" + (7 - (profileData.daily_streak || 0) === 1 ? "" : "s") + " to 7-day milestone"}
                      </p>
                    </div>
                  </div>
                )}

                {/* W/L Tally + Accuracy */}
                {profilePicks.length > 0 && (() => {
                  const resolved  = profilePicks.filter(p => p.result !== "pending");
                  const wins      = profilePicks.filter(p => p.result === "correct").length;
                  const losses    = profilePicks.filter(p => p.result === "wrong").length;
                  const pending   = profilePicks.filter(p => p.result === "pending").length;
                  const accuracy  = resolved.length > 0 ? Math.round((wins / resolved.length) * 100) : null;
                  const accColor  = accuracy == null ? "#4a4958" : accuracy >= 60 ? "#22c55e" : accuracy >= 40 ? "#f59e0b" : "#ef4444";
                  return (
                    <div style={{ padding: "8px 16px 0" }}>
                      {/* W / L / Pending tally row */}
                      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8, marginBottom: 8 }}>
                        <div style={{ background: "#0a1a0a", border: "0.5px solid #22c55e30", borderRadius: 10, padding: "10px 8px", textAlign: "center" }}>
                          <p style={{ margin: "0 0 2px", fontSize: 22, fontWeight: 900, color: "#22c55e", lineHeight: 1 }}>{wins}</p>
                          <p style={{ margin: 0, fontSize: 10, fontWeight: 700, color: "#22c55e80", textTransform: "uppercase", letterSpacing: ".05em" }}>Correct</p>
                        </div>
                        <div style={{ background: "#1a0a0a", border: "0.5px solid #ef444430", borderRadius: 10, padding: "10px 8px", textAlign: "center" }}>
                          <p style={{ margin: "0 0 2px", fontSize: 22, fontWeight: 900, color: "#ef4444", lineHeight: 1 }}>{losses}</p>
                          <p style={{ margin: 0, fontSize: 10, fontWeight: 700, color: "#ef444480", textTransform: "uppercase", letterSpacing: ".05em" }}>Wrong</p>
                        </div>
                        <div style={{ background: "#1a1a0a", border: "0.5px solid #f59e0b30", borderRadius: 10, padding: "10px 8px", textAlign: "center" }}>
                          <p style={{ margin: "0 0 2px", fontSize: 22, fontWeight: 900, color: "#f59e0b", lineHeight: 1 }}>{pending}</p>
                          <p style={{ margin: 0, fontSize: 10, fontWeight: 700, color: "#f59e0b80", textTransform: "uppercase", letterSpacing: ".05em" }}>Pending</p>
                        </div>
                      </div>
                      {/* Accuracy bar */}
                      {accuracy != null && (
                        <div style={{ ...s.statCard }}>
                          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}>
                            <p style={{ fontSize: 11, color: "#4a4958", margin: 0, textTransform: "uppercase", letterSpacing: ".05em" }}>Accuracy</p>
                            <p style={{ fontSize: 16, fontWeight: 800, margin: 0, color: accColor }}>{accuracy}%</p>
                          </div>
                          <div style={{ background: "#2a2a32", borderRadius: 4, height: 6, overflow: "hidden" }}>
                            <div style={{ width: accuracy + "%", height: "100%", background: accColor, borderRadius: 4, transition: "width .4s" }} />
                          </div>
                          {resolved.length > 0 && (
                            <p style={{ fontSize: 10, color: "#4a4958", margin: "6px 0 0", textAlign: "right" }}>{resolved.length} resolved prediction{resolved.length !== 1 ? "s" : ""}</p>
                          )}
                        </div>
                      )}
                    </div>
                  );
                })()}

                {/* Momentum chart */}
                {profilePicks.filter(p => p.result !== "pending").length >= 2 && (
                  <div style={{ padding: "8px 16px 0" }}>
                    <div style={{ ...s.statCard }}>
                      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 12 }}>
                        <div>
                          <p style={{ fontSize: 11, color: "#4a4958", margin: "0 0 2px", textTransform: "uppercase", letterSpacing: ".05em" }}>Momentum</p>
                          <p style={{ fontSize: 12, color: "#8b8a99", margin: 0 }}>Last {Math.min(profilePicks.filter(p => p.result !== "pending").length, 10)} picks</p>
                        </div>
                        {(() => {
                          const resolved = profilePicks.filter(p => p.result !== "pending");
                          const last10 = resolved.slice(0, 10).reverse();
                          const recent5 = last10.slice(-5);
                          const older5  = last10.slice(0, last10.length - 5);
                          if (older5.length === 0) return null;
                          const recentAcc = recent5.filter(p => p.result === "correct").length / recent5.length;
                          const olderAcc  = older5.filter(p => p.result === "correct").length / older5.length;
                          const trend = recentAcc - olderAcc;
                          return (
                            <span style={{ fontSize: 12, fontWeight: 600, padding: "3px 8px", borderRadius: 99, background: trend >= 0.1 ? "#22c55e20" : trend <= -0.1 ? "#ef444420" : "#f59e0b20", color: trend >= 0.1 ? "#22c55e" : trend <= -0.1 ? "#ef4444" : "#f59e0b" }}>
                              {trend >= 0.1 ? "↑ Hot" : trend <= -0.1 ? "↓ Cold" : "→ Steady"}
                            </span>
                          );
                        })()}
                      </div>
                      <MomentumChart picks={profilePicks} />
                      <div style={{ display: "flex", justifyContent: "space-between", marginTop: 8 }}>
                        <span style={{ fontSize: 10, color: "#4a4958" }}>← oldest</span>
                        <div style={{ display: "flex", gap: 10 }}>
                          <span style={{ fontSize: 10, color: "#22c55e" }}>● Correct</span>
                          <span style={{ fontSize: 10, color: "#ef4444" }}>● Wrong</span>
                        </div>
                        <span style={{ fontSize: 10, color: "#4a4958" }}>latest →</span>
                      </div>
                    </div>
                  </div>
                )}

                {/* Prediction calendar shortcut — own profile only */}
                {!viewingProfile && (
                  <div style={{ padding: "8px 16px 0" }}>
                    <button onClick={() => { loadCalendarPicks(); setScreen("calendar"); }} style={{ width: "100%", background: "linear-gradient(135deg, #0d0d1a, #130f1f)", border: "0.5px solid #2a2040", borderRadius: 12, padding: "12px 16px", display: "flex", alignItems: "center", justifyContent: "space-between", cursor: "pointer" }}>
                      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                        <span style={{ fontSize: 20 }}>📅</span>
                        <div style={{ textAlign: "left" }}>
                          <p style={{ margin: 0, fontSize: 13, fontWeight: 700, color: "#f0eff8" }}>Prediction Calendar</p>
                          <p style={{ margin: "2px 0 0", fontSize: 11, color: "#4a4958" }}>View daily & correct streaks</p>
                        </div>
                      </div>
                      <span style={{ fontSize: 16, color: "#4a4958" }}>›</span>
                    </button>
                  </div>
                )}

                {/* Notification settings — own profile only */}
                {!viewingProfile && (
                  <div style={{ padding: "12px 16px 0" }}>
                    <p style={s.sectionLabel}>Notifications</p>
                    <div style={{ background: "#13131c", border: "0.5px solid #2a2040", borderRadius: 12, overflow: "hidden" }}>
                      <button
                        onClick={async () => {
                          if (!notifyOnPick) {
                            const granted = await requestNotificationPermission();
                            if (granted) setNotifyOnPick(true);
                          } else {
                            setNotifyOnPick(false);
                          }
                        }}
                        style={{ width: "100%", display: "flex", alignItems: "center", justifyContent: "space-between", padding: "14px 16px", background: "none", border: "none", cursor: "pointer" }}>
                        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                          <span style={{ fontSize: 20 }}>{notifyOnPick ? "🔔" : "🔕"}</span>
                          <div style={{ textAlign: "left" }}>
                            <p style={{ margin: 0, fontSize: 14, fontWeight: 600, color: "#f0eff8" }}>Match reminders</p>
                            <p style={{ margin: "2px 0 0", fontSize: 12, color: "#4a4958" }}>Get notified 30 min before each predicted match</p>
                          </div>
                        </div>
                        <div style={{ width: 40, height: 22, borderRadius: 11, background: notifyOnPick ? "#6c63ff" : "#2a2a36", display: "flex", alignItems: "center", padding: "0 3px", flexShrink: 0, transition: "background .2s" }}>
                          <div style={{ width: 16, height: 16, borderRadius: "50%", background: "#fff", transform: notifyOnPick ? "translateX(18px)" : "translateX(0)", transition: "transform .2s" }} />
                        </div>
                      </button>
                    </div>
                  </div>
                )}

                {/* Pick history */}
                <div style={{ padding: "12px 16px 0" }}>
                  <p style={s.sectionLabel}>Recent picks</p>
                  {profilePicks.length === 0
                    ? <p style={{ fontSize: 13, color: "#4a4958", padding: "8px 0" }}>No picks yet</p>
                    : profilePicks.map((p, i) => (
                      <div key={i} style={s.card}>
                        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
                          <div style={{ flex: 1 }}>
                            <div style={{ display: "flex", alignItems: "center", gap: 6, marginBottom: 3 }}>
                              <p style={{ fontSize: 14, fontWeight: 600, color: "#f0eff8", margin: 0 }}>{p.market}</p>
                              {p.difficulty && <DiffBadge d={p.difficulty} />}
                            </div>
                            <p style={{ fontSize: 12, color: "#4a4958", margin: "2px 0 0" }}>{p.match}</p>
                            <p style={{ fontSize: 11, color: "#4a4958", marginTop: 3 }}>{p.confidence}% confidence{p.odds ? " · " + p.odds + " odds" : ""}</p>
                          </div>
                          <div style={{ textAlign: "right", flexShrink: 0, marginLeft: 8 }}>
                            <ResultBadge result={p.result} />
                            {p.result === "correct" && p.points_earned != null && <p style={{ fontSize: 12, fontWeight: 700, color: "#22c55e", marginTop: 3 }}>+{p.points_earned} pts</p>}
                            {p.result === "wrong"   && p.points_earned != null && <p style={{ fontSize: 12, fontWeight: 700, color: "#ef4444", marginTop: 3 }}>{p.points_earned} pts</p>}
                          </div>
                        </div>
                      </div>
                    ))
                  }
                </div>
              </>
            )}
          </div>

          {!viewingProfile || viewingProfile === user?.id
            ? <BottomNav screen={screen} setScreen={id => { if (id === "profile") setViewingProfile(null); setScreen(id); }} nav={NAV} />
            : null
          }
        </div>
      )}

      {/* ── Leaderboard ──────────────────────────────────── */}
      {screen === "leaderboard" && (
        <div style={s.screen}>
          <div style={s.header}>
            <span style={s.logo}>Leaderboard</span>
            <button onClick={() => loadLeaderboard(lbTab)} style={{ background: "none", border: "none", color: "#6c63ff", fontSize: 12, cursor: "pointer" }}>Refresh</button>
          </div>
          <div style={{ flex: 1, minHeight: 0, overflowY: "auto" }}>
            <div style={{ padding: "12px 16px 0" }}>
              <div style={s.toggle}>
                {["weekly","alltime"].map(t => (
                  <button key={t} onClick={() => setLbTab(t)} style={{ ...s.toggleBtn, ...(lbTab===t ? s.toggleBtnOn : {}) }}>
                    {t === "weekly" ? "This week" : "All time"}
                  </button>
                ))}
              </div>
              {/* Trial mode banner */}
              {profile?.is_anonymous && (
                <div style={{ background: "#f59e0b12", border: "0.5px solid #f59e0b44", borderRadius: 10, padding: "10px 12px", marginBottom: 10, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                  <div>
                    <p style={{ margin: "0 0 2px", fontSize: 12, fontWeight: 700, color: "#f59e0b" }}>👻 Trial account</p>
                    <p style={{ margin: 0, fontSize: 11, color: "#4a4958" }}>Add email to save permanently</p>
                  </div>
                  <button onClick={() => { setEmail(""); setPassword(""); setAuthScreen("upgrade"); }} style={{ background: "#f59e0b", border: "none", color: "#000", fontSize: 11, fontWeight: 700, padding: "5px 10px", borderRadius: 6, cursor: "pointer", flexShrink: 0 }}>Save</button>
                </div>
              )}
              {lbLoading && <p style={{ fontSize: 13, color: "#4a4958", padding: "8px 0" }}>Loading...</p>}
              {!lbLoading && lbData.length === 0 && <p style={{ fontSize: 13, color: "#4a4958", padding: "8px 0" }}>No data yet — make some picks!</p>}
              {!lbLoading && lbData.map((p, i) => {
                const isMe   = p.id === user?.id;
                const pts    = lbTab === "weekly" ? p.weekly_points : p.total_points;
                const isTop3 = i < 3;
                const medals = ["🥇","🥈","🥉"];
                return (
                  <button key={p.id} onClick={() => openProfile(p.id)} style={{ ...s.card, border: isMe ? "0.5px solid #6c63ff" : "0.5px solid #2a2a32", background: isMe ? "#6c63ff0a" : "#1a1a1f", marginBottom: 8, width: "100%", cursor: "pointer", textAlign: "left" }}>
                    <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                      <div style={{ width: 32, textAlign: "center", flexShrink: 0 }}>
                        {isTop3 ? <span style={{ fontSize: 18 }}>{medals[i]}</span> : <span style={{ fontSize: 13, color: "#4a4958", fontWeight: 600 }}>{i+1}</span>}
                      </div>
                      <div style={{ ...s.avatar, width: 36, height: 36, fontSize: 13, background: isMe ? "#6c63ff22" : "#1a1a2f", border: `0.5px solid ${isMe ? "#6c63ff66" : "#2a2a32"}`, color: isMe ? "#8a83ff" : "#8b8a99" }}>
                        {p.username?.[0]?.toUpperCase() ?? "?"}
                      </div>
                      <div style={{ flex: 1 }}>
                        <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                          <p style={{ margin: 0, fontSize: 14, fontWeight: 600, color: isMe ? "#8a83ff" : "#f0eff8" }}>{p.username ?? "Unknown"}</p>
                          {isMe && <span style={{ fontSize: 10, color: "#6c63ff", fontWeight: 600 }}>you</span>}
                          {p.current_streak >= 3 && <span style={{ fontSize: 10, fontWeight: 600, padding: "1px 5px", borderRadius: 99, background: "#ef444420", color: "#ef4444" }}>{p.current_streak >= 5 ? "🔥" : "⚡"}{p.current_streak}</span>}
                        </div>
                        <div style={{ display: "flex", gap: 10, marginTop: 2 }}>
                          <span style={{ fontSize: 11, color: "#4a4958" }}>{p.total} picks</span>
                          {p.accuracy != null && <span style={{ fontSize: 11, color: "#4a4958" }}>{p.accuracy}% accuracy</span>}
                        </div>
                      </div>
                      <div style={{ textAlign: "right", flexShrink: 0 }}>
                        <p style={{ margin: 0, fontSize: 18, fontWeight: 700, color: isTop3 ? "#f59e0b" : isMe ? "#8a83ff" : "#f0eff8" }}>{pts ?? 0}</p>
                        <p style={{ margin: 0, fontSize: 11, color: "#4a4958" }}>pts</p>
                      </div>
                    </div>
                  </button>
                );
              })}
            </div>
          </div>
          <BottomNav screen={screen} setScreen={id => { if (id === "profile") setViewingProfile(null); setScreen(id); }} nav={NAV} />
        </div>
      )}

      {/* ── Admin ────────────────────────────────────────── */}
      {screen === "admin" && isAdmin && (
        <div style={s.screen}>
          <div style={{ ...s.header, background: "#1a0a0a", borderBottom: "0.5px solid #ef444430" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
              <button style={s.back} onClick={() => { setScreen("feed"); setAdminMsg({ text:"", ok:true }); }}>← Back</button>
              <span style={{ ...s.logo, color: "#ef4444" }}>Admin Panel</span>
            </div>
            <span style={{ fontSize: 11, background: "#ef444420", color: "#ef4444", padding: "2px 8px", borderRadius: 4, fontWeight: 600 }}>RESTRICTED</span>
          </div>
          <div style={{ display: "flex", borderBottom: "0.5px solid #2a2a32" }}>
            {[{ id:"settle", label:"Settlement" },{ id:"override", label:"Override" },{ id:"simulate", label:"Simulate" }].map(t => (
              <button key={t.id} onClick={() => { setAdminTab(t.id); setAdminMsg({ text:"",ok:true }); }} style={{ flex: 1, padding: "10px 4px", border: "none", background: "none", cursor: "pointer", fontSize: 12, fontWeight: adminTab===t.id ? 600 : 400, color: adminTab===t.id ? "#ef4444" : "#4a4958", borderBottom: adminTab===t.id ? "2px solid #ef4444" : "2px solid transparent" }}>{t.label}</button>
            ))}
          </div>
          <div style={{ flex: 1, overflowY: "auto", padding: "16px 16px 24px" }}>
            {adminMsg.text && (
              <div style={{ background: adminMsg.ok ? "#22c55e15" : "#ef444415", border: `0.5px solid ${adminMsg.ok ? "#22c55e44" : "#ef444444"}`, borderRadius: 8, padding: "10px 14px", marginBottom: 16, fontSize: 13, color: adminMsg.ok ? "#22c55e" : "#ef4444" }}>{adminMsg.text}</div>
            )}
            {adminTab === "settle" && (
              <div>
                <p style={s.adminSectionTitle}>Bulk settle a match</p>
                <p style={{ fontSize: 12, color: "#4a4958", marginBottom: 16, lineHeight: 1.6 }}>Enter the final score to auto-resolve all picks for that match.</p>
                <p style={s.fieldLabel}>Match</p>
                <select value={settleMatch} onChange={e => setSettleMatch(e.target.value)} style={{ ...s.input, marginBottom: 16 }}>
                  <option value="">Select a match...</option>
                  {[...new Set(adminPicks.map(p => p.match))].map(m => <option key={m} value={m}>{m}</option>)}
                </select>
                <p style={s.fieldLabel}>Final score</p>
                <div style={{ display: "grid", gridTemplateColumns: "1fr 40px 1fr", gap: 8, marginBottom: 20, alignItems: "center" }}>
                  <input type="number" min="0" max="20" placeholder="Home" value={homeScore} onChange={e => setHomeScore(e.target.value)} style={{ ...s.input, marginBottom: 0, textAlign: "center" }} />
                  <p style={{ textAlign: "center", color: "#4a4958", fontWeight: 700, margin: 0 }}>–</p>
                  <input type="number" min="0" max="20" placeholder="Away" value={awayScore} onChange={e => setAwayScore(e.target.value)} style={{ ...s.input, marginBottom: 0, textAlign: "center" }} />
                </div>
                <button style={{ ...s.adminBtn, opacity: settleLoading ? 0.6 : 1 }} onClick={handleSettle} disabled={settleLoading}>{settleLoading ? "Settling..." : "Settle all picks for this match"}</button>
                {settleResult && !settleResult.error && (
                  <div style={{ marginTop: 16, background: "#1a1a1f", border: "0.5px solid #2a2a32", borderRadius: 10, padding: 14 }}>
                    <p style={{ fontSize: 13, fontWeight: 600, color: "#f0eff8", margin: "0 0 10px" }}>{settleResult.settled} picks resolved</p>
                    {settleResult.results?.map((r, i) => (
                      <div key={i} style={{ display: "flex", justifyContent: "space-between", fontSize: 12, padding: "5px 0", borderBottom: "0.5px solid #2a2a32" }}>
                        <span style={{ color: "#8b8a99" }}>{r.market}</span>
                        {r.skipped ? <span style={{ color: "#4a4958" }}>Manual required</span> : <span style={{ color: r.result === "correct" ? "#22c55e" : "#ef4444", fontWeight: 600 }}>{r.result === "correct" ? `+${r.pointsEarned}` : r.pointsEarned} pts</span>}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            )}
            {adminTab === "override" && (
              <div>
                <p style={s.adminSectionTitle}>Manual pick override</p>
                <p style={{ fontSize: 12, color: "#4a4958", marginBottom: 16, lineHeight: 1.6 }}>Manually mark individual picks as correct or wrong.</p>
                {adminLoading && <p style={{ fontSize: 13, color: "#4a4958" }}>Loading...</p>}
                {!adminLoading && adminPicks.length === 0 && <p style={{ fontSize: 13, color: "#4a4958" }}>No pending picks.</p>}
                {!adminLoading && adminPicks.map(p => (
                  <div key={p.id} style={{ ...s.card, marginBottom: 10 }}>
                    <div style={{ marginBottom: 10 }}>
                      <div style={{ display: "flex", alignItems: "center", gap: 6, marginBottom: 4 }}>
                        <div style={s.avatar}>{p.profiles?.username?.[0] ?? "?"}</div>
                        <span style={{ fontSize: 13, fontWeight: 600, color: "#f0eff8" }}>{p.profiles?.username ?? "Unknown"}</span>
                        {p.difficulty && <DiffBadge d={p.difficulty} />}
                      </div>
                      <p style={{ fontSize: 14, fontWeight: 600, color: "#f0eff8", margin: "0 0 2px" }}>{p.market}</p>
                      <p style={{ fontSize: 12, color: "#8b8a99", margin: 0 }}>{p.match}</p>
                      <div style={{ display: "flex", gap: 12, marginTop: 5, fontSize: 11, color: "#4a4958" }}>
                        <span>{p.confidence}% conf</span>
                        {p.odds && <span>{p.odds} odds</span>}
                        <span style={{ color: "#22c55e" }}>+{p.points_possible} win</span>
                        <span style={{ color: "#ef4444" }}>-{p.points_lost} lose</span>
                      </div>
                    </div>
                    <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8 }}>
                      <button onClick={() => resolvePick(p.id, "correct")} disabled={resolvingId===p.id} style={{ ...s.resolveBtn, borderColor: "#22c55e", background: "#22c55e15", color: "#22c55e", opacity: resolvingId===p.id ? 0.5 : 1 }}>{resolvingId===p.id ? "..." : "Correct"}</button>
                      <button onClick={() => resolvePick(p.id, "wrong")} disabled={resolvingId===p.id} style={{ ...s.resolveBtn, borderColor: "#ef4444", background: "#ef444415", color: "#ef4444", opacity: resolvingId===p.id ? 0.5 : 1 }}>{resolvingId===p.id ? "..." : "Wrong"}</button>
                    </div>
                  </div>
                ))}
              </div>
            )}
            {adminTab === "simulate" && (
              <div>
                <p style={s.adminSectionTitle}>Simulation mode</p>
                <p style={{ fontSize: 12, color: "#4a4958", marginBottom: 16, lineHeight: 1.6 }}>Preview points impact — nothing gets saved.</p>
                <p style={s.fieldLabel}>Select match</p>
                {[...new Set(adminPicks.map(p => p.match))].length === 0
                  ? <p style={{ fontSize: 13, color: "#ef4444", marginBottom: 16, background: "#ef444415", border: "0.5px solid #ef444444", borderRadius: 8, padding: "10px 14px" }}>No pending picks found. Make some picks first then come back here.</p>
                  : (
                    <select value={simMatch} onChange={e => { setSimMatch(e.target.value); setSimPicks([]); setSimOutput(null); setSimLeaderboard(null); }} style={{ ...s.input, marginBottom: 8 }}>
                      <option value="">Choose a match...</option>
                      {[...new Set(adminPicks.map(p => p.match))].map(m => (
                        <option key={m} value={m}>{m}</option>
                      ))}
                    </select>
                  )
                }
                <button onClick={loadSimPicks} disabled={!simMatch} style={{ ...s.adminBtn, background: "#2a2a32", color: "#f0eff8", border: "0.5px solid #3a3a42", marginBottom: 16, opacity: simMatch ? 1 : 0.4 }}>Load picks</button>
                {simPicks.length > 0 && (
                  <>
                    <p style={{ fontSize: 12, color: "#4a4958", marginBottom: 8 }}>{simPicks.length} picks found — set each result below</p>

                    {/* Bulk toggle buttons */}
                    <div style={{ display: "flex", gap: 8, marginBottom: 12 }}>
                      <button onClick={() => { const all = {}; simPicks.forEach(p => { all[p.id] = "correct"; }); setPerPickResults(all); }} style={{ flex: 1, padding: "7px", borderRadius: 8, border: "0.5px solid #22c55e", background: "#22c55e15", color: "#22c55e", fontSize: 12, fontWeight: 600, cursor: "pointer" }}>All correct</button>
                      <button onClick={() => { const all = {}; simPicks.forEach(p => { all[p.id] = "wrong"; }); setPerPickResults(all); }} style={{ flex: 1, padding: "7px", borderRadius: 8, border: "0.5px solid #ef4444", background: "#ef444415", color: "#ef4444", fontSize: 12, fontWeight: 600, cursor: "pointer" }}>All wrong</button>
                    </div>

                    {/* Per-pick result selector */}
                    <div style={{ background: "#1a1a1f", border: "0.5px solid #2a2a32", borderRadius: 10, marginBottom: 12, overflow: "hidden" }}>
                      {simPicks.map((p, i) => {
                        const res = perPickResults[p.id] || "correct";
                        return (
                          <div key={p.id} style={{ padding: "10px 14px", borderBottom: i < simPicks.length - 1 ? "0.5px solid #2a2a32" : "none" }}>
                            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 8 }}>
                              <div>
                                <p style={{ margin: 0, fontSize: 13, fontWeight: 600, color: "#f0eff8" }}>{p.profiles?.username ?? "Unknown"}</p>
                                <p style={{ margin: 0, fontSize: 11, color: "#4a4958" }}>{p.market}</p>
                                <p style={{ margin: 0, fontSize: 11, color: "#4a4958" }}>{p.confidence}% conf{p.odds ? " · " + p.odds + " odds" : ""}</p>
                              </div>
                              {p.difficulty && <span style={{ fontSize: 10, fontWeight: 600, padding: "1px 6px", borderRadius: 99, background: (p.difficulty === "hard" ? "#ef4444" : p.difficulty === "medium" ? "#f59e0b" : "#22c55e") + "20", color: p.difficulty === "hard" ? "#ef4444" : p.difficulty === "medium" ? "#f59e0b" : "#22c55e" }}>{p.difficulty}</span>}
                            </div>
                            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 6 }}>
                              <button onClick={() => setPerPickResults(prev => ({ ...prev, [p.id]: "correct" }))} style={{ padding: "6px", borderRadius: 6, border: "0.5px solid " + (res === "correct" ? "#22c55e" : "#2a2a32"), background: res === "correct" ? "#22c55e20" : "transparent", color: res === "correct" ? "#22c55e" : "#4a4958", fontSize: 12, fontWeight: res === "correct" ? 600 : 400, cursor: "pointer" }}>Correct</button>
                              <button onClick={() => setPerPickResults(prev => ({ ...prev, [p.id]: "wrong" }))} style={{ padding: "6px", borderRadius: 6, border: "0.5px solid " + (res === "wrong" ? "#ef4444" : "#2a2a32"), background: res === "wrong" ? "#ef444420" : "transparent", color: res === "wrong" ? "#ef4444" : "#4a4958", fontSize: 12, fontWeight: res === "wrong" ? 600 : 400, cursor: "pointer" }}>Wrong</button>
                            </div>
                          </div>
                        );
                      })}
                    </div>

                    <button onClick={handleSimulate} style={{ ...s.adminBtn, marginBottom: 16, opacity: simLoading ? 0.6 : 1 }} disabled={simLoading}>{simLoading ? "Simulating..." : "Run simulation"}</button>
                  </>
                )}
                {simOutput && (
                  <div>
                    {/* Per-pick breakdown */}
                    <div style={{ background: "#1a1a1f", border: "0.5px solid #2a2a32", borderRadius: 10, padding: 14, marginBottom: 12 }}>
                      <p style={{ fontSize: 12, color: "#4a4958", margin: "0 0 10px", fontWeight: 600, letterSpacing: ".05em" }}>PICK BREAKDOWN — NOT SAVED</p>
                      {simOutput.map((r, i) => (
                        <div key={i} style={{ padding: "9px 0", borderBottom: i < simOutput.length - 1 ? "0.5px solid #2a2a32" : "none" }}>
                          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
                            <div>
                              <p style={{ margin: 0, fontSize: 13, color: "#f0eff8", fontWeight: 500 }}>{r.username}</p>
                              <p style={{ margin: 0, fontSize: 11, color: "#4a4958" }}>{r.market} · {r.confidence}% conf{r.odds ? " · " + r.odds + " odds" : ""}</p>
                            </div>
                            <div style={{ textAlign: "right" }}>
                              <span style={{ fontSize: 14, fontWeight: 700, color: r.points > 0 ? "#22c55e" : "#ef4444" }}>{r.points > 0 ? "+" + r.points : r.points} pts</span>
                              {r.streakMult > 1 && (
                                <p style={{ margin: 0, fontSize: 10, color: "#f59e0b" }}>{r.basePoints} x {r.streakMult} streak</p>
                              )}
                            </div>
                          </div>
                          {/* Streak info row */}
                          <div style={{ display: "flex", gap: 8, marginTop: 5 }}>
                            <span style={{ fontSize: 10, color: "#4a4958" }}>
                              Streak: {r.streakBefore} → {r.streakAfter}
                            </span>
                            {r.streakMult > 1 && (
                              <span style={{ fontSize: 10, fontWeight: 600, padding: "1px 6px", borderRadius: 99, background: r.streakMult >= 2 ? "#ef444420" : "#f59e0b20", color: r.streakMult >= 2 ? "#ef4444" : "#f59e0b" }}>
                                {r.streakMult}x bonus
                              </span>
                            )}
                            {r.result === "wrong" && r.streakBefore > 0 && (
                              <span style={{ fontSize: 10, fontWeight: 600, padding: "1px 6px", borderRadius: 99, background: "#ef444420", color: "#ef4444" }}>
                                streak broken
                              </span>
                            )}
                          </div>
                        </div>
                      ))}
                      <p style={{ fontSize: 11, color: "#4a4958", marginTop: 10, textAlign: "center" }}>
                        Net: {simOutput.reduce((a, b) => a + b.points, 0) >= 0 ? "+" : ""}{simOutput.reduce((a, b) => a + b.points, 0)} pts across all affected users
                      </p>
                    </div>

                    {/* Simulated leaderboard */}
                    {simLeaderboard && (
                      <div style={{ background: "#1a1a1f", border: "0.5px solid #2a2a32", borderRadius: 10, padding: 14 }}>
                        <p style={{ fontSize: 12, color: "#4a4958", margin: "0 0 10px", fontWeight: 600, letterSpacing: ".05em" }}>SIMULATED LEADERBOARD</p>
                        {simLeaderboard.filter(p => (p.total_points || 0) > 0 || p.delta !== 0).slice(0, 10).map((p, i) => (
                          <div key={p.id} style={{ display: "flex", alignItems: "center", gap: 10, padding: "8px 0", borderBottom: i < 9 ? "0.5px solid #2a2a32" : "none" }}>
                            {/* Rank change indicator */}
                            <div style={{ width: 28, textAlign: "center", flexShrink: 0 }}>
                              <p style={{ margin: 0, fontSize: 13, fontWeight: 700, color: "#f0eff8" }}>{p.simRank}</p>
                              {p.rankDelta > 0 && <p style={{ margin: 0, fontSize: 10, color: "#22c55e" }}>+{p.rankDelta}</p>}
                              {p.rankDelta < 0 && <p style={{ margin: 0, fontSize: 10, color: "#ef4444" }}>{p.rankDelta}</p>}
                              {p.rankDelta === 0 && <p style={{ margin: 0, fontSize: 10, color: "#4a4958" }}>—</p>}
                            </div>

                            {/* Avatar */}
                            <div style={{ width: 28, height: 28, borderRadius: "50%", background: p.id === user?.id ? "#6c63ff22" : "#2a2a32", border: "0.5px solid " + (p.id === user?.id ? "#6c63ff66" : "#3a3a42"), color: p.id === user?.id ? "#8a83ff" : "#8b8a99", fontSize: 11, fontWeight: 600, display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
                              {p.username?.[0]?.toUpperCase() ?? "?"}
                            </div>

                            {/* Name */}
                            <div style={{ flex: 1 }}>
                              <p style={{ margin: 0, fontSize: 13, fontWeight: 600, color: p.id === user?.id ? "#8a83ff" : "#f0eff8" }}>{p.is_anonymous ? "👻 " : ""}
                                {p.username}
                                {p.id === user?.id && <span style={{ fontSize: 10, color: "#6c63ff", marginLeft: 5 }}>you</span>}
                              </p>
                            </div>

                            {/* Points: current → simulated */}
                            <div style={{ textAlign: "right", flexShrink: 0 }}>
                              <p style={{ margin: 0, fontSize: 14, fontWeight: 700, color: "#f0eff8" }}>{p.simTotal}</p>
                              {p.delta !== 0 && (
                                <p style={{ margin: 0, fontSize: 10, color: p.delta > 0 ? "#22c55e" : "#ef4444" }}>
                                  {p.delta > 0 ? "+" : ""}{p.delta} pts
                                </p>
                              )}
                            </div>
                          </div>
                        ))}
                        <p style={{ fontSize: 11, color: "#4a4958", marginTop: 10, textAlign: "center" }}>Showing top 10 · Greyed ranks = no change</p>
                      </div>
                    )}
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      )}

      {/* ── Leagues ─────────────────────────────────────── */}
      {screen === "leagues" && user && profile?.is_anonymous && (
        <div style={s.screen}>
          <div style={s.header}><span style={s.logo}>Leagues</span></div>
          <div style={{ display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", flex: 1, padding: "0 28px", textAlign: "center" }}>
            <p style={{ fontSize: 40, margin: "0 0 12px" }}>🏆</p>
            <p style={{ margin: "0 0 8px", fontSize: 18, fontWeight: 700, color: "#f0eff8" }}>Leagues</p>
            <p style={{ margin: "0 0 24px", fontSize: 13, color: "#8b8a99", lineHeight: 1.6 }}>Create private leagues and compete with friends. Requires a free account.</p>
            <button onClick={() => { setEmail(""); setPassword(""); setAuthScreen("upgrade"); }} style={{ width: "100%", padding: "14px", borderRadius: 12, border: "none", background: "linear-gradient(135deg, #6c63ff, #8a83ff)", color: "#fff", fontSize: 15, fontWeight: 700, cursor: "pointer" }}>
              Create free account
            </button>
          </div>
          <BottomNav screen={screen} setScreen={id => setScreen(id)} nav={NAV} />
        </div>
      )}
      {screen === "leagues" && user && !profile?.is_anonymous && (
        <div style={s.screen}>
          <div style={s.header}>
            {leagueView
              ? <button style={s.back} onClick={() => { setLeagueView(null); setLeagueMembers([]); }}>← Back</button>
              : <span style={s.logo}>Leagues</span>
            }
            {leagueView
              ? <span style={s.logo}>{leagueView.name}</span>
              : <div style={{ display: "flex", gap: 8 }}>
                  <button onClick={() => { setLeagueAction("join"); setLeagueMsg({ text:"",ok:true }); }} style={{ background: "none", border: "0.5px solid #2a2a32", color: "#8b8a99", fontSize: 12, padding: "4px 10px", borderRadius: 6, cursor: "pointer" }}>Join</button>
                  <button onClick={() => { setLeagueAction("create"); setLeagueMsg({ text:"",ok:true }); }} style={{ background: "#6c63ff", border: "none", color: "#fff", fontSize: 12, fontWeight: 600, padding: "4px 10px", borderRadius: 6, cursor: "pointer" }}>+ Create</button>
                </div>
            }
          </div>

          <div style={{ flex: 1, overflowY: "auto", padding: "16px 16px 0" }}>

            {/* Message */}
            {leagueMsg.text && (
              <div style={{ background: leagueMsg.ok ? "#22c55e15" : "#ef444415", border: "0.5px solid " + (leagueMsg.ok ? "#22c55e44" : "#ef444444"), borderRadius: 8, padding: "10px 14px", marginBottom: 14, fontSize: 13, color: leagueMsg.ok ? "#22c55e" : "#ef4444" }}>
                {leagueMsg.text}
              </div>
            )}

            {/* ── League detail view ── */}
            {leagueView && (
              <div>
                {/* Invite code card */}
                <div style={{ ...s.statCard, marginBottom: 14, border: "0.5px solid #6c63ff44" }}>
                  <p style={s.statLabel}>Invite code</p>
                  <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginTop: 4 }}>
                    <p style={{ margin: 0, fontSize: 28, fontWeight: 700, color: "#8a83ff", letterSpacing: ".15em" }}>{leagueView.invite_code}</p>
                    <button onClick={() => copyCode(leagueView.invite_code)} style={{ background: copied ? "#22c55e20" : "#6c63ff20", border: "0.5px solid " + (copied ? "#22c55e44" : "#6c63ff44"), color: copied ? "#22c55e" : "#8a83ff", fontSize: 12, fontWeight: 600, padding: "5px 12px", borderRadius: 8, cursor: "pointer" }}>
                      {copied ? "Copied!" : "Copy"}
                    </button>
                  </div>
                  <p style={{ margin: "6px 0 0", fontSize: 11, color: "#4a4958" }}>Share this code with friends so they can join</p>
                </div>

                {/* Members leaderboard */}
                <p style={s.sectionLabel}>Members — {leagueMembers.length}</p>
                {leagueMembLoad && <p style={{ fontSize: 13, color: "#4a4958" }}>Loading...</p>}
                {!leagueMembLoad && leagueMembers.map((m, i) => {
                  const isMe   = m.id === user?.id;
                  const medals = ["🥇","🥈","🥉"];
                  return (
                    <div key={m.id} style={{ ...s.card, border: isMe ? "0.5px solid #6c63ff" : "0.5px solid #2a2a32", background: isMe ? "#6c63ff0a" : "#1a1a1f", marginBottom: 8 }}>
                      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                        <div style={{ width: 28, textAlign: "center", flexShrink: 0 }}>
                          {i < 3 ? <span style={{ fontSize: 16 }}>{medals[i]}</span> : <span style={{ fontSize: 13, color: "#4a4958", fontWeight: 600 }}>{i+1}</span>}
                        </div>
                        <div style={{ ...s.avatar, width: 34, height: 34, fontSize: 13, background: isMe ? "#6c63ff22" : "#2a2a32", border: "0.5px solid " + (isMe ? "#6c63ff66" : "#3a3a42"), color: isMe ? "#8a83ff" : "#8b8a99" }}>
                          {m.username?.[0]?.toUpperCase() ?? "?"}
                        </div>
                        <div style={{ flex: 1 }}>
                          <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                            <p style={{ margin: 0, fontSize: 13, fontWeight: 600, color: isMe ? "#8a83ff" : "#f0eff8" }}>{m.username}</p>
                            {isMe && <span style={{ fontSize: 10, color: "#6c63ff", fontWeight: 600 }}>you</span>}
                          </div>
                          {(m.current_streak || 0) >= 3 && (
                            <span style={{ fontSize: 10, color: "#f59e0b" }}>{m.current_streak} win streak</span>
                          )}
                        </div>
                        <div style={{ textAlign: "right" }}>
                          <p style={{ margin: 0, fontSize: 16, fontWeight: 700, color: i < 3 ? "#f59e0b" : isMe ? "#8a83ff" : "#f0eff8" }}>{m.total_points ?? 0}</p>
                          <p style={{ margin: 0, fontSize: 11, color: "#4a4958" }}>pts</p>
                        </div>
                      </div>
                    </div>
                  );
                })}

                {/* Invite by email */}
                <div style={{ marginTop: 16, background: "#13131c", border: "0.5px solid #2a2040", borderRadius: 12, padding: "14px" }}>
                  <p style={{ margin: "0 0 6px", fontSize: 13, fontWeight: 700, color: "#f0eff8" }}>Invite by email</p>
                  <p style={{ margin: "0 0 10px", fontSize: 11, color: "#4a4958", lineHeight: 1.5 }}>Enter a friend's account email to add them directly — they must already have a Predkt account.</p>
                  {inviteMsg.text && (
                    <div style={{ background: inviteMsg.ok ? "#22c55e15" : "#ef444415", border: "0.5px solid " + (inviteMsg.ok ? "#22c55e44" : "#ef444444"), borderRadius: 8, padding: "8px 12px", marginBottom: 10, fontSize: 12, color: inviteMsg.ok ? "#22c55e" : "#ef4444" }}>
                      {inviteMsg.text}
                    </div>
                  )}
                  <div style={{ display: "flex", gap: 8 }}>
                    <input
                      type="email"
                      placeholder="friend@email.com"
                      value={inviteEmail}
                      onChange={e => { setInviteEmail(e.target.value); setInviteMsg({ text: "", ok: true }); }}
                      onKeyDown={e => e.key === "Enter" && handleInviteByEmail()}
                      style={{ ...s.input, flex: 1, marginBottom: 0, fontSize: 13 }}
                    />
                    <button
                      onClick={handleInviteByEmail}
                      disabled={inviteLoading || !inviteEmail.trim()}
                      style={{ padding: "10px 14px", borderRadius: 10, border: "none", background: inviteEmail.trim() ? "#6c63ff" : "#1e1e28", color: inviteEmail.trim() ? "#fff" : "#3a3a50", fontSize: 13, fontWeight: 700, cursor: inviteEmail.trim() ? "pointer" : "default", flexShrink: 0 }}>
                      {inviteLoading ? "..." : "Invite"}
                    </button>
                  </div>
                </div>

                {/* Leave league */}
                {leagueView.creator_id !== user?.id && (
                  <button onClick={() => handleLeaveLeague(leagueView.id)} style={{ width: "100%", marginTop: 8, padding: "10px", borderRadius: 10, border: "0.5px solid #ef444444", background: "#ef444415", color: "#ef4444", fontSize: 13, fontWeight: 600, cursor: "pointer" }}>
                    Leave league
                  </button>
                )}
              </div>
            )}

            {/* ── League list ── */}
            {!leagueView && leagueAction === "list" && (
              <div>
                {leagueLoading && <p style={{ fontSize: 13, color: "#4a4958" }}>Loading...</p>}
                {!leagueLoading && myLeagues.length === 0 && (
                  <div style={{ textAlign: "center", padding: "40px 0" }}>
                    <p style={{ fontSize: 32, marginBottom: 12 }}>🏆</p>
                    <p style={{ fontSize: 15, fontWeight: 600, color: "#f0eff8", margin: "0 0 6px" }}>No leagues yet</p>
                    <p style={{ fontSize: 13, color: "#4a4958", margin: 0 }}>Create one or join a friend's league</p>
                  </div>
                )}
                {!leagueLoading && myLeagues.map(lg => (
                  <button key={lg.id} onClick={() => { setLeagueView(lg); loadLeagueMembers(lg.id); }} style={{ ...s.card, width: "100%", textAlign: "left", cursor: "pointer", marginBottom: 10, border: "0.5px solid #2a2a32" }}>
                    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                      <div>
                        <p style={{ margin: 0, fontSize: 14, fontWeight: 600, color: "#f0eff8" }}>{lg.name}</p>
                        <p style={{ margin: 0, fontSize: 11, color: "#4a4958", marginTop: 2 }}>Code: {lg.invite_code}</p>
                      </div>
                      <span style={{ color: "#4a4958", fontSize: 16 }}>›</span>
                    </div>
                  </button>
                ))}
              </div>
            )}

            {/* ── Create league ── */}
            {!leagueView && leagueAction === "create" && (
              <div>
                <p style={{ fontSize: 13, color: "#4a4958", marginBottom: 16, lineHeight: 1.6 }}>Give your league a name — you will get a 6-letter invite code to share with friends.</p>
                <p style={s.fieldLabel}>League name</p>
                <input type="text" placeholder="e.g. The Sharps, Friday Five..." value={createName} onChange={e => setCreateName(e.target.value)} style={{ ...s.input }} />
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8 }}>
                  <button onClick={() => { setLeagueAction("list"); setLeagueMsg({ text:"",ok:true }); }} style={{ padding: 12, borderRadius: 10, border: "0.5px solid #2a2a32", background: "transparent", color: "#8b8a99", fontSize: 13, cursor: "pointer" }}>Cancel</button>
                  <button onClick={handleCreateLeague} disabled={leagueActLoading} style={{ ...s.primaryBtn, opacity: leagueActLoading ? 0.6 : 1 }}>{leagueActLoading ? "Creating..." : "Create"}</button>
                </div>
              </div>
            )}

            {/* ── Join league ── */}
            {!leagueView && leagueAction === "join" && (
              <div>
                <p style={{ fontSize: 13, color: "#4a4958", marginBottom: 16, lineHeight: 1.6 }}>Enter the 6-letter invite code from a friend to join their league.</p>
                <p style={s.fieldLabel}>Invite code</p>
                <input type="text" placeholder="e.g. ABC123" value={joinCode} onChange={e => setJoinCode(e.target.value.toUpperCase())} maxLength={6} style={{ ...s.input, letterSpacing: ".15em", fontSize: 18, fontWeight: 700, textAlign: "center" }} />
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8 }}>
                  <button onClick={() => { setLeagueAction("list"); setLeagueMsg({ text:"",ok:true }); }} style={{ padding: 12, borderRadius: 10, border: "0.5px solid #2a2a32", background: "transparent", color: "#8b8a99", fontSize: 13, cursor: "pointer" }}>Cancel</button>
                  <button onClick={handleJoinLeague} disabled={leagueActLoading} style={{ ...s.primaryBtn, opacity: leagueActLoading ? 0.6 : 1 }}>{leagueActLoading ? "Joining..." : "Join league"}</button>
                </div>
              </div>
            )}
          </div>

          <BottomNav screen={screen} setScreen={id => { if (id === "profile") setViewingProfile(null); setLeagueView(null); setLeagueAction("list"); setLeagueMsg({ text:"",ok:true }); setScreen(id); }} nav={NAV} />
        </div>
      )}

      {/* ── Predict ──────────────────────────────────────── */}
      {screen === "predict" && (
        <div style={{ ...s.screen, background: "#0d0b18", position: "relative" }}>

          {/* Header */}
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "14px 16px 10px", borderBottom: "0.5px solid #221a35", background: "#100d1e", flexShrink: 0 }}>
            <button style={s.back} onClick={() => { setScreen("feed"); setBetslip([]); setSelectedMarket(null); setMarkets([]); setPredictView("list"); }}>← Back</button>
            <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
              <span style={{ fontSize: 15, fontWeight: 800, color: "#f0eff8", letterSpacing: "-.01em" }}>
                {predictView === "detail" && match ? match.home + " vs " + match.away : "Predictions"}
              </span>
              {liveMatches.filter(m => m.isLive).length > 0 && (
                <span style={{ fontSize: 9, fontWeight: 800, padding: "2px 6px", borderRadius: 99, background: "#22c55e", color: "#000", letterSpacing: ".03em" }}>
                  {liveMatches.filter(m => m.isLive).length} LIVE
                </span>
              )}
            </div>
            {/* Betslip tab */}
            <button onClick={() => { setSlipOpen(o => !o); }} style={{ position: "relative", background: betslip.length > 0 ? "#f59e0b" : "#1e1e2a", border: "none", borderRadius: 8, padding: "5px 10px", cursor: "pointer", display: "flex", alignItems: "center", gap: 5 }}>
              <svg width="14" height="14" viewBox="0 0 20 20" fill="none"><rect x="3" y="2" width="14" height="16" rx="2" stroke={betslip.length > 0 ? "#000" : "#8a83ff"} strokeWidth="1.5"/><path d="M7 7h6M7 11h4" stroke={betslip.length > 0 ? "#000" : "#8a83ff"} strokeWidth="1.5" strokeLinecap="round"/></svg>
              <span style={{ fontSize: 12, fontWeight: 800, color: betslip.length > 0 ? "#000" : "#8a83ff" }}>
                {betslip.length > 0 ? betslip.length + " picks" : "Picks"}
              </span>
            </button>
          </div>

          {/* Trial warning bar for anonymous users */}
          {profile?.is_anonymous && (() => {
            const created  = new Date(user?.created_at || 0);
            const hoursLeft = Math.max(0, 72 - (Date.now() - created.getTime()) / 3600000);
            const pct       = Math.max(0, hoursLeft / 72 * 100);
            if (hoursLeft <= 0) return null;
            return (
              <button onClick={() => { setEmail(""); setPassword(""); setAuthScreen("upgrade"); }} style={{ background: "#1a1408", borderBottom: "0.5px solid #f59e0b44", padding: "7px 14px", display: "flex", alignItems: "center", gap: 8, width: "100%", border: "none", cursor: "pointer", borderTop: "none", borderLeft: "none", borderRight: "none" }}>
                <div style={{ flex: 1, background: "#2a2a1a", borderRadius: 3, height: 4, overflow: "hidden" }}>
                  <div style={{ width: pct + "%", height: "100%", background: pct > 30 ? "#f59e0b" : "#ef4444", borderRadius: 3 }} />
                </div>
                <span style={{ fontSize: 10, color: "#f59e0b", fontWeight: 700, flexShrink: 0 }}>{Math.ceil(hoursLeft)}h left · Save progress</span>
              </button>
            );
          })()}
          {/* Mode hint */}
          <div style={{ background: "#0f0c1c", borderBottom: "0.5px solid #221a35", padding: "6px 14px", display: "flex", alignItems: "center", justifyContent: "space-between", flexShrink: 0 }}>
            <span style={{ fontSize: 10, color: "#4a4958", fontWeight: 600 }}>
              {betslip.length === 0 ? "Tap any odds to add to your slip" : betslip.length === 1 ? "Single · Add more for a combo" : betslip.length === 2 ? "Double" : betslip.length === 3 ? "Treble" : betslip.length + "-Fold Accumulator"}
            </span>
            <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
              <span style={{ fontSize: 10, fontWeight: 700, color: myPicks.length >= 5 ? "#ef4444" : myPicks.length >= 4 ? "#f59e0b" : "#4a4958" }}>
                {5 - myPicks.length} left today
              </span>
              {betslip.length > 0 && (
                <button onClick={() => { setBetslip([]); setSelectedMarket(null); setSlipOpen(false); }} style={{ background: "none", border: "none", color: "#4a4958", fontSize: 10, cursor: "pointer", padding: 0 }}>Clear all</button>
              )}
            </div>
          </div>

          {/* Middle wrapper: content + betslip flex column — BottomNav sits outside this */}
          <div style={{ flex: 1, minHeight: 0, display: "flex", flexDirection: "column", overflow: "hidden" }}>

          {/* Content area */}
          <div style={{ flex: 1, minHeight: 0, overflowY: "auto", paddingBottom: 16 }}>

            {/* Acca builder summary bar */}
            {slipMode === "acca" && betslip.length > 0 && !slipOpen && (
              <div style={{ background: "#1a1400", borderBottom: "0.5px solid #f59e0b44", padding: "8px 16px", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                <div style={{ display: "flex", gap: 6, flexWrap: "wrap", flex: 1 }}>
                  {betslip.map((p, i) => (
                    <span key={i} style={{ fontSize: 10, background: "#f59e0b20", color: "#f59e0b", padding: "2px 7px", borderRadius: 4, fontWeight: 600 }}>{p.label}</span>
                  ))}
                </div>
                <span style={{ fontSize: 14, fontWeight: 800, color: "#f59e0b", marginLeft: 8, flexShrink: 0 }}>
                  {parseFloat(betslip.reduce((a, p) => a * (p.odds || 2), 1).toFixed(2))}x
                </span>
              </div>
            )}

            {/* Match list - show when in list view */}
            {predictView === "list" && (() => {
              const { q, filtered, favMatches, entries, isFavLeagueComp, isFavTeamMatch } = predictList;
              const todayStr   = new Date().toISOString().split("T")[0];
              const matchDates = Array.from({ length: 14 }, (_, i) => {
                const d = new Date(); d.setDate(d.getDate() + i);
                return d.toISOString().split("T")[0];
              });

              return (
                <div style={{ padding: "10px 12px 0" }}>

                  {/* ── Date navigation bar ── */}
                  {!matchesLoading && matchDates.length > 0 && (
                    <div style={{ display: "flex", gap: 6, overflowX: "auto", paddingBottom: 4, marginBottom: 10, scrollbarWidth: "none", msOverflowStyle: "none" }}>
                      {matchDates.map(d => {
                        const isActive = d === selectedDate;
                        const isToday  = d === todayStr;
                        const dt = new Date(d + "T12:00:00");
                        const dayLabel  = isToday ? "Today" : dt.toLocaleDateString("en-GB", { weekday: "short" });
                        const dateNum   = dt.toLocaleDateString("en-GB", { day: "numeric" });
                        const monthStr  = dt.toLocaleDateString("en-GB", { month: "short" });
                        const matchCount = dateMatchCounts[d] || 0;
                        return (
                          <button key={d} onClick={() => { setSelectedDate(d); setMatchSearch(""); }} style={{ flexShrink: 0, padding: "8px 10px", borderRadius: 10, border: isActive ? "none" : "0.5px solid #1e1e2a", background: isActive ? "linear-gradient(135deg, #6c63ff, #8a83ff)" : "#111118", cursor: "pointer", textAlign: "center", minWidth: 54, boxShadow: isActive ? "0 4px 14px #6c63ff40" : "none" }}>
                            <p style={{ margin: 0, fontSize: 9, color: isActive ? "rgba(255,255,255,0.75)" : "#4a4958", fontWeight: 700, textTransform: "uppercase", letterSpacing: ".04em" }}>{dayLabel}</p>
                            <p style={{ margin: "3px 0 1px", fontSize: 18, fontWeight: 900, color: isActive ? "#fff" : "#c8c7d4", lineHeight: 1 }}>{dateNum}</p>
                            <p style={{ margin: 0, fontSize: 9, color: isActive ? "rgba(255,255,255,0.75)" : "#4a4958", fontWeight: 600 }}>{monthStr}</p>
                            {matchCount > 0 && (
                              <p style={{ margin: "3px 0 0", fontSize: 9, fontWeight: 700, color: isActive ? "rgba(255,255,255,0.9)" : "#3a3a50" }}>{matchCount}</p>
                            )}
                          </button>
                        );
                      })}
                    </div>
                  )}

                  {/* Search */}
                  <div style={{ display: "flex", alignItems: "center", gap: 8, background: "#16112a", border: "0.5px solid #2d2250", borderRadius: 8, padding: "8px 12px", marginBottom: 12 }}>
                    <svg width="13" height="13" viewBox="0 0 20 20" fill="none"><circle cx="9" cy="9" r="6" stroke="#4a4958" strokeWidth="1.5"/><path d="M13.5 13.5L17 17" stroke="#4a4958" strokeWidth="1.5" strokeLinecap="round"/></svg>
                    <input type="text" placeholder="Search team or league..." value={matchSearch} onChange={e => setMatchSearch(e.target.value)} style={{ background: "none", border: "none", outline: "none", color: "#f0eff8", fontSize: 13, flex: 1 }} />
                    {matchSearch && <button onClick={() => setMatchSearch("")} style={{ background: "none", border: "none", color: "#4a4958", cursor: "pointer", padding: 0, fontSize: 16 }}>×</button>}
                  </div>

                  {matchesLoading && <p style={{ fontSize: 13, color: "#4a4958", textAlign: "center", padding: "20px 0" }}>Loading fixtures...</p>}

                  {matchesError && !matchesLoading && (
                    <div style={{ textAlign: "center", padding: "30px 20px" }}>
                      <p style={{ fontSize: 13, color: "#ef4444", marginBottom: 12 }}>{matchesError}</p>
                      <button onClick={loadMatches} style={{ padding: "8px 20px", borderRadius: 8, background: "#6c63ff", color: "#fff", border: "none", fontSize: 13, cursor: "pointer", fontWeight: 600 }}>Retry</button>
                    </div>
                  )}

                  {!matchesLoading && !matchesError && matches.length === 0 && (
                    <div style={{ textAlign: "center", padding: "30px 20px" }}>
                      <p style={{ fontSize: 13, color: "#4a4958", marginBottom: 12 }}>No upcoming fixtures found.</p>
                      <button onClick={loadMatches} style={{ padding: "8px 20px", borderRadius: 8, background: "#1e1e2a", color: "#8a83ff", border: "0.5px solid #2a2a32", fontSize: 13, cursor: "pointer", fontWeight: 600 }}>Refresh</button>
                    </div>
                  )}

                  {/* No matches for selected date */}
                  {!matchesLoading && !matchesError && matches.length > 0 && !q && filtered.length === 0 && (
                    <div style={{ textAlign: "center", padding: "30px 20px" }}>
                      <p style={{ fontSize: 22, marginBottom: 8 }}>📭</p>
                      <p style={{ fontSize: 13, color: "#8b8a99", marginBottom: 4 }}>No fixtures on this date</p>
                      <p style={{ fontSize: 11, color: "#4a4958" }}>Try another day above</p>
                    </div>
                  )}

                  {/* ── Live Now section ── */}
                  {liveMatches.filter(lm => lm.isLive).length > 0 && (
                    <div style={{ marginBottom: 16 }}>
                      <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 8 }}>
                        <span style={{ fontSize: 9, fontWeight: 800, padding: "2px 6px", borderRadius: 4, background: "#22c55e", color: "#000" }}>LIVE</span>
                        <span style={{ fontSize: 10, fontWeight: 800, color: "#22c55e", textTransform: "uppercase", letterSpacing: ".08em" }}>Matches in progress</span>
                      </div>
                      <div style={{ display: "flex", gap: 8, overflowX: "auto", paddingBottom: 4, scrollbarWidth: "none" }}>
                        {liveMatches.filter(lm => lm.isLive).map(lm => (
                          <div key={lm.fixtureId} style={{ flexShrink: 0, background: "#0d1a10", border: "0.5px solid #22c55e55", borderRadius: 10, padding: "10px 12px", minWidth: 150, textAlign: "center" }}>
                            <div style={{ fontSize: 9, fontWeight: 800, color: "#22c55e", marginBottom: 4 }}>
                              {lm.status === "HT" ? "Half Time" : `${lm.elapsed ?? 0}'`}
                            </div>
                            <div style={{ fontSize: 12, fontWeight: 700, color: "#e0ffe8", marginBottom: 2, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{lm.home}</div>
                            <div style={{ fontSize: 20, fontWeight: 900, color: "#22c55e", lineHeight: 1.1, marginBottom: 2 }}>{lm.homeGoals} – {lm.awayGoals}</div>
                            <div style={{ fontSize: 12, fontWeight: 700, color: "#e0ffe8", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{lm.away}</div>
                            <div style={{ fontSize: 9, color: "#4a4958", marginTop: 4 }}>{lm.competition}</div>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* ── Popular Builders — pinned at top ── */}
                  {!matchesLoading && matches.length > 0 && (() => {
                    return (
                      <div style={{ marginBottom: 16 }}>
                        <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 8 }}>
                          <span style={{ fontSize: 10, fontWeight: 800, color: "#f59e0b", textTransform: "uppercase", letterSpacing: ".08em" }}>⚡ Quick Picks</span>
                          <span style={{ fontSize: 9, color: "#4a4958" }}>Tap a match first, then add</span>
                        </div>
                        <div style={{ display: "flex", gap: 8, overflowX: "auto", paddingBottom: 4, scrollbarWidth: "none" }}>
                          {QUICK_BUILDERS.map((b, bi) => {
                            // Check if all picks from this builder are in slip for the active match
                            const activeMatch = match;
                            const allIn = activeMatch && b.picks.every(pk => betslip.some(p => p.key === pk + "_" + activeMatch.id));
                            return (
                              <button key={bi} onClick={() => {
                                if (!activeMatch) { setSlipError("Tap a match first to use a builder"); setTimeout(() => setSlipError(""), 2500); return; }
                                if (allIn) { setBetslip(bs => bs.filter(p => !b.picks.some(pk => p.key === pk + "_" + activeMatch.id))); return; }
                                // Load odds first if not loaded, then add
                                if (markets.length === 0) { loadOdds(activeMatch); return; }
                                b.picks.forEach(pk => {
                                  const market = markets.flatMap(g => g.options).find(o => o.key === pk || pk.includes(o.key) || o.key.includes(pk));
                                  if (market) handleAddToSlip(market, activeMatch.id, activeMatch.home + " vs " + activeMatch.away, "Builder");
                                });
                              }} style={{ flexShrink: 0, background: allIn ? "#1a1200" : "#111118", border: allIn ? "1.5px solid #f59e0b" : "0.5px solid #1e1e28", borderRadius: 10, padding: "8px 12px", cursor: "pointer", textAlign: "left", minWidth: 140 }}>
                                <p style={{ margin: "0 0 3px", fontSize: 16 }}>{b.emoji}</p>
                                <p style={{ margin: "0 0 2px", fontSize: 11, fontWeight: 700, color: allIn ? "#f59e0b" : "#e0dff0" }}>{b.name}</p>
                                <p style={{ margin: 0, fontSize: 9, color: "#4a4958", lineHeight: 1.3 }}>{b.desc}</p>
                                {allIn && <p style={{ margin: "4px 0 0", fontSize: 9, color: "#f59e0b", fontWeight: 700 }}>✓ In slip</p>}
                              </button>
                            );
                          })}
                        </div>
                      </div>
                    );
                  })()}

                  {/* ── Your teams pinned section ── */}
                  {!q && favMatches.length > 0 && (
                    <div style={{ marginBottom: 16 }}>
                      <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "6px 4px", borderBottom: "0.5px solid #3a2a60", marginBottom: 6 }}>
                        <span style={{ fontSize: 10, fontWeight: 800, color: "#a098ff", textTransform: "uppercase", letterSpacing: ".08em", flex: 1 }}>⭐ Your teams</span>
                        <span style={{ fontSize: 9, color: "#4a3a60", fontWeight: 700, paddingRight: 6 }}>H&nbsp;&nbsp;&nbsp;&nbsp;D&nbsp;&nbsp;&nbsp;&nbsp;A</span>
                      </div>
                      {favMatches.map(m => {
                        const isActive = match?.id === m.id;
                        const cardOdds = matchOdds[m.fixtureId];
                        const lm = findLiveMatch(liveMatches, m.home, m.away, m.fixtureId);
                        return (
                          <div key={"fav_" + m.id} style={{ background: isActive ? "#1a1535" : lm?.isLive ? "#0d1a10" : "#130f20", border: isActive ? "1px solid #8a83ff55" : lm?.isLive ? "0.5px solid #22c55e55" : "0.5px solid #2d2060", borderRadius: 10, marginBottom: 6, overflow: "hidden" }}>
                            <button onClick={() => { setMatch(m); setPredictView("detail"); loadOdds(m); setSelectedMarket(null); }} style={{ width: "100%", display: "flex", alignItems: "center", padding: "11px 12px", background: "none", border: "none", cursor: "pointer", textAlign: "left", gap: 10 }}>
                              <span style={{ fontSize: 9, color: "#8a83ff", flexShrink: 0 }}>★</span>
                              <div style={{ flex: 1, minWidth: 0 }}>
                                <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 6 }}>
                                  <Crest url={m.homeCrest} size={22} />
                                  <span style={{ fontSize: 14, fontWeight: 700, color: "#ffffff", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{m.home}</span>
                                  {lm?.isLive && <span style={{ fontSize: 16, fontWeight: 900, color: "#22c55e", marginLeft: "auto", flexShrink: 0 }}>{lm.homeGoals}</span>}
                                  {lm?.isFinished && <span style={{ fontSize: 16, fontWeight: 900, color: "#6a6080", marginLeft: "auto", flexShrink: 0 }}>{lm.homeGoals}</span>}
                                </div>
                                <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                                  <Crest url={m.awayCrest} size={22} />
                                  <span style={{ fontSize: 14, fontWeight: 700, color: "#ffffff", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{m.away}</span>
                                  {lm?.isLive && <span style={{ fontSize: 16, fontWeight: 900, color: "#22c55e", marginLeft: "auto", flexShrink: 0 }}>{lm.awayGoals}</span>}
                                  {lm?.isFinished && <span style={{ fontSize: 16, fontWeight: 900, color: "#6a6080", marginLeft: "auto", flexShrink: 0 }}>{lm.awayGoals}</span>}
                                </div>
                                {lm?.isLive ? (
                                  <div style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 5 }}>
                                    <span style={{ fontSize: 9, fontWeight: 800, padding: "1px 5px", borderRadius: 4, background: "#22c55e", color: "#000" }}>LIVE</span>
                                    <span style={{ fontSize: 10, color: "#22c55e", fontWeight: 700 }}>{lm.elapsed ?? 0}'</span>
                                    {lm.status === "HT" && <span style={{ fontSize: 9, color: "#f59e0b", fontWeight: 700 }}>HT</span>}
                                  </div>
                                ) : lm?.isFinished ? (
                                  <div style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 5 }}>
                                    <span style={{ fontSize: 9, fontWeight: 700, padding: "1px 5px", borderRadius: 4, background: "#2a2a3a", color: "#6a6080" }}>FT</span>
                                  </div>
                                ) : (
                                  <span style={{ fontSize: 10, color: "#7a6e9a", display: "block", marginTop: 5 }}>{m.time} · {m.competition}</span>
                                )}
                              </div>
                              <div style={{ display: "flex", gap: 5, flexShrink: 0 }}>
                                {[0,1,2].map(i => {
                                  const opt = Array.isArray(cardOdds) ? cardOdds[i] : null;
                                  const inSlip = opt && (slipMode === "acca" ? betslip.some(p => p.key === opt.key + "_" + m.id) : selectedMarket?.key === opt.key);
                                  return (
                                    <button key={i} onClick={opt ? e => { e.stopPropagation(); handleAddToSlip(opt, m.id, m.home + " vs " + m.away, "Match result"); } : e => e.stopPropagation()}
                                      style={{ minWidth: 42, padding: "6px 4px", borderRadius: 8, border: inSlip ? "1.5px solid #f59e0b" : opt ? "0.5px solid #2d2250" : "0.5px solid #1e1530", background: inSlip ? "#f59e0b18" : opt ? "#1c1535" : "#130f1e", cursor: opt ? "pointer" : "default", textAlign: "center" }}>
                                      <p style={{ margin: 0, fontSize: 9, color: inSlip ? "#f59e0b" : "#5a4a7a", fontWeight: 700 }}>{["H","D","A"][i]}</p>
                                      <p style={{ margin: "3px 0 0", fontSize: 13, fontWeight: 800, color: inSlip ? "#f59e0b" : opt ? "#e8e0ff" : "#2d2450" }}>
                                        {cardOdds === undefined ? "·" : opt?.odds ?? "—"}
                                      </p>
                                    </button>
                                  );
                                })}
                              </div>
                              <span style={{ fontSize: 12, color: "#3a2d55", marginLeft: 2 }}>›</span>
                            </button>
                          </div>
                        );
                      })}
                    </div>
                  )}

                  {entries.map(([comp, compMatches]) => {
                    const isFavLeague = isFavLeagueComp(comp);
                    return (
                      <div key={comp} style={{ marginBottom: 16 }}>
                        {/* League header */}
                        <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "6px 4px", borderBottom: "0.5px solid #221a35", marginBottom: 6 }}>
                          <span style={{ fontSize: 10, fontWeight: 800, color: isFavLeague ? "#f59e0b" : "#6b5f8a", textTransform: "uppercase", letterSpacing: ".08em", flex: 1 }}>
                            {isFavLeague ? "⭐ " : ""}{comp}
                          </span>
                          <span style={{ fontSize: 9, color: "#4a3a60", fontWeight: 700, paddingRight: 6 }}>H&nbsp;&nbsp;&nbsp;&nbsp;D&nbsp;&nbsp;&nbsp;&nbsp;A</span>
                        </div>

                        {/* Match rows */}
                        {compMatches.map(m => {
                          const isActive = match?.id === m.id;
                          const isFavMatch = favTeams.length > 0 && isFavTeamMatch(m);
                          const cardOdds = matchOdds[m.fixtureId]; // undefined=loading, null=none, array=loaded
                          const lm = findLiveMatch(liveMatches, m.home, m.away, m.fixtureId);

                          return (
                            <div key={m.id} style={{ background: isActive ? "#1a1535" : lm?.isLive ? "#0d1a10" : "#130f20", border: isActive ? "1px solid #6c63ff55" : lm?.isLive ? "0.5px solid #22c55e55" : lm?.isFinished ? "0.5px solid #2a2a35" : "0.5px solid #221a35", borderRadius: 10, marginBottom: 6, overflow: "hidden" }}>
                              <button onClick={() => { setMatch(m); setPredictView("detail"); loadOdds(m); setSelectedMarket(null); }} style={{ width: "100%", display: "flex", alignItems: "center", padding: "11px 12px", background: "none", border: "none", cursor: "pointer", textAlign: "left", gap: 10 }}>
                                {isFavMatch && <span style={{ fontSize: 9, color: "#f59e0b", flexShrink: 0 }}>★</span>}
                                <div style={{ flex: 1, minWidth: 0 }}>
                                  <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 6 }}>
                                    <Crest url={m.homeCrest} size={22} />
                                    <span style={{ fontSize: 14, fontWeight: 700, color: lm?.isLive ? "#ffffff" : "#ffffff", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{m.home}</span>
                                    {lm?.isLive && <span style={{ fontSize: 16, fontWeight: 900, color: "#22c55e", marginLeft: "auto", flexShrink: 0 }}>{lm.homeGoals}</span>}
                                    {lm?.isFinished && <span style={{ fontSize: 16, fontWeight: 900, color: "#6a6080", marginLeft: "auto", flexShrink: 0 }}>{lm.homeGoals}</span>}
                                  </div>
                                  <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                                    <Crest url={m.awayCrest} size={22} />
                                    <span style={{ fontSize: 14, fontWeight: 700, color: "#ffffff", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{m.away}</span>
                                    {lm?.isLive && <span style={{ fontSize: 16, fontWeight: 900, color: "#22c55e", marginLeft: "auto", flexShrink: 0 }}>{lm.awayGoals}</span>}
                                    {lm?.isFinished && <span style={{ fontSize: 16, fontWeight: 900, color: "#6a6080", marginLeft: "auto", flexShrink: 0 }}>{lm.awayGoals}</span>}
                                  </div>
                                  {lm?.isLive ? (
                                    <div style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 5 }}>
                                      <span style={{ fontSize: 9, fontWeight: 800, padding: "1px 5px", borderRadius: 4, background: "#22c55e", color: "#000" }}>LIVE</span>
                                      <span style={{ fontSize: 10, color: "#22c55e", fontWeight: 700 }}>{lm.elapsed ?? 0}'</span>
                                      {lm.status === "HT" && <span style={{ fontSize: 9, color: "#f59e0b", fontWeight: 700 }}>HT</span>}
                                    </div>
                                  ) : lm?.isFinished ? (
                                    <div style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 5 }}>
                                      <span style={{ fontSize: 9, fontWeight: 700, padding: "1px 5px", borderRadius: 4, background: "#2a2a3a", color: "#6a6080" }}>FT</span>
                                    </div>
                                  ) : (
                                    <span style={{ fontSize: 10, color: "#7a6e9a", display: "block", marginTop: 5 }}>{m.time}</span>
                                  )}
                                </div>
                                {/* H/D/A odds — always visible, populated from matchOdds map */}
                                <div style={{ display: "flex", gap: 5, flexShrink: 0 }}>
                                  {[0,1,2].map(i => {
                                    const opt = Array.isArray(cardOdds) ? cardOdds[i] : null;
                                    const inSlip = opt && (slipMode === "acca" ? betslip.some(p => p.key === opt.key + "_" + m.id) : selectedMarket?.key === opt.key);
                                    return (
                                      <button key={i} onClick={opt ? e => { e.stopPropagation(); handleAddToSlip(opt, m.id, m.home + " vs " + m.away, "Match result"); } : e => e.stopPropagation()}
                                        style={{ minWidth: 42, padding: "6px 4px", borderRadius: 8, border: inSlip ? "1.5px solid #f59e0b" : opt ? "0.5px solid #2d2250" : "0.5px solid #1e1530", background: inSlip ? "#f59e0b18" : opt ? "#1c1535" : "#130f1e", cursor: opt ? "pointer" : "default", textAlign: "center" }}>
                                        <p style={{ margin: 0, fontSize: 9, color: inSlip ? "#f59e0b" : "#5a4a7a", fontWeight: 700 }}>{["H","D","A"][i]}</p>
                                        <p style={{ margin: "3px 0 0", fontSize: 13, fontWeight: 800, color: inSlip ? "#f59e0b" : opt ? "#e8e0ff" : "#2d2450" }}>
                                          {cardOdds === undefined ? "·" : opt?.odds ?? "—"}
                                        </p>
                                      </button>
                                    );
                                  })}
                                </div>
                                <span style={{ fontSize: 12, color: "#3a2d55", marginLeft: 2 }}>›</span>
                              </button>
                            </div>
                          );
                        })}
                      </div>
                    );
                  })}
                </div>
              );
            })()}

            {/* Detail view — Bet365 tabbed market design */}
            {predictView === "detail" && match && (
              <div style={{ display: "flex", flexDirection: "column", height: "100%" }}>

                {/* Back button row */}
                <div style={{ padding: "6px 12px 4px", display: "flex", alignItems: "center", justifyContent: "space-between", flexShrink: 0 }}>
                  <button onClick={() => { setPredictView("list"); setSelectedMarket(null); setMarkets([]); }} style={{ display: "flex", alignItems: "center", gap: 4, background: "none", border: "none", color: "#8a83ff", fontSize: 12, cursor: "pointer", padding: 0, fontWeight: 600 }}>
                    ← Matches
                  </button>
                  {oddsLive
                    ? <span style={{ fontSize: 9, fontWeight: 700, padding: "2px 7px", borderRadius: 99, background: "#22c55e20", border: "0.5px solid #22c55e", color: "#22c55e" }}>● LIVE</span>
                    : <span style={{ fontSize: 9, fontWeight: 700, padding: "2px 7px", borderRadius: 99, background: "#1e1e2a", color: "#4a4958" }}>EST.</span>
                  }
                </div>

                {/* Error toast */}
                {slipError && (
                  <div style={{ margin: "0 12px 6px", background: "#f59e0b15", border: "0.5px solid #f59e0b44", borderRadius: 8, padding: "7px 12px", fontSize: 12, color: "#f59e0b", fontWeight: 600, flexShrink: 0 }}>
                    ⚠ {slipError}
                  </div>
                )}

                {/* ── Swipeable category tabs (Bet365 style) ── */}
                {!marketsLoading && markets.length > 0 && (
                  <div style={{ flexShrink: 0, borderBottom: "0.5px solid #221a35", background: "#100d1e" }}>
                    <div style={{ display: "flex", overflowX: "auto", scrollbarWidth: "none", padding: "0 12px" }}>
                      {markets.map((group, gi) => {
                        const hasSelection = group.options.some(o => betslip.some(p => p.key === o.key + "_" + match.id));
                        return (
                          <button key={gi} onClick={() => setMarketTab(gi)} style={{ flexShrink: 0, padding: "9px 14px", border: "none", background: "none", cursor: "pointer", fontSize: 12, fontWeight: marketTab === gi ? 700 : 400, color: marketTab === gi ? "#f59e0b" : "#4a4958", borderBottom: marketTab === gi ? "2px solid #f59e0b" : "2px solid transparent", whiteSpace: "nowrap", position: "relative" }}>
                            {group.category}
                            {hasSelection && <span style={{ position: "absolute", top: 6, right: 6, width: 6, height: 6, borderRadius: "50%", background: "#f59e0b" }} />}
                          </button>
                        );
                      })}
                    </div>
                  </div>
                )}

                {/* Market content — shows active tab only */}
                <div style={{ flex: 1, overflowY: "auto", padding: "10px 12px" }}>
                  {marketsLoading && <p style={{ fontSize: 13, color: "#4a4958", textAlign: "center", padding: "20px 0" }}>Loading odds...</p>}
                {!marketsLoading && !oddsLive && markets.length > 0 && (
                  <div style={{ background: "#1a1200", border: "0.5px solid #f59e0b44", borderRadius: 8, padding: "8px 12px", marginBottom: 10, display: "flex", alignItems: "center", gap: 8 }}>
                    <span style={{ fontSize: 14 }}>⚠️</span>
                    <p style={{ margin: 0, fontSize: 12, color: "#f59e0b" }}>Live odds not available for this match yet — predictions using estimated odds are still allowed</p>
                  </div>
                )}

                  {!marketsLoading && markets[marketTab] && (() => {
                    const group = markets[marketTab];
                    return (
                      <div>
                        {group.category === "Match result" || group.options.length <= 3 ? (
                          /* Grid layout for 3-option markets */
                          <div style={{ display: "grid", gridTemplateColumns: "repeat(" + Math.min(group.options.length, 3) + ", 1fr)", gap: 6 }}>
                            {group.options.map((opt, oi) => {
                              const inSlip = betslip.some(p => p.key === opt.key + "_" + match.id) || selectedMarket?.key === opt.key;
                              const diff   = getDifficulty(opt.label);
                              const val    = getValueLabel(opt.odds);
                              const pts    = opt.odds ? calcPointsWinCapped(opt.odds, conf, diff.key) : null;
                              return (
                                <div key={oi} style={{ position: "relative" }}>
                                  <button
                                    onClick={() => opt.odds ? handleAddToSlip(opt, match.id, match.home + " vs " + match.away, group.category) : null}
                                    disabled={!opt.odds}
                                    style={{ width: "100%", padding: "12px 6px 8px", borderRadius: 10, border: inSlip ? "2px solid #f59e0b" : !opt.odds ? "0.5px solid #1a1a20" : "0.5px solid #1e1e2a", background: inSlip ? "#1a1200" : !opt.odds ? "#0c0c10" : "#111118", cursor: opt.odds ? "pointer" : "not-allowed", textAlign: "center", transition: "all .1s", opacity: opt.odds ? 1 : 0.5 }}>
                                    <p style={{ margin: "0 0 4px", fontSize: 10, color: inSlip ? "#f59e0b" : !opt.odds ? "#2a2a3a" : "#5a5a70", fontWeight: 700, textTransform: "uppercase" }}>{opt.label.replace(" win","").replace("Win","")}</p>
                                    {opt.odds
                                      ? <p style={{ margin: 0, fontSize: 22, fontWeight: 900, color: inSlip ? "#f59e0b" : "#e0dff0", lineHeight: 1 }}>{opt.odds}</p>
                                      : <p style={{ margin: 0, fontSize: 10, color: "#2a2a3a", fontWeight: 600 }}>Not available</p>
                                    }
                                    {opt.odds && val && <p style={{ margin: "4px 0 0", fontSize: 9, color: inSlip ? "#f59e0b" : val.color }}>{inSlip ? "✓ Added" : val.label}</p>}
                                    {pts && !inSlip && <p style={{ margin: "2px 0 0", fontSize: 9, color: "#22c55e80" }}>+{pts} pts</p>}
                                  </button>
                                  {opt.odds && <button onClick={e => { e.stopPropagation(); setFormulaModal({ opt, diff }); }} style={{ position: "absolute", top: 4, right: 4, background: "none", border: "none", color: "#2a2a3a", cursor: "pointer", fontSize: 12, padding: 2, lineHeight: 1 }}>ⓘ</button>}
                                </div>
                              );
                            })}
                          </div>
                        ) : (
                          /* List layout for multi-option markets */
                          <div style={{ display: "flex", flexDirection: "column", gap: 5 }}>
                            {group.options.map((opt, oi) => {
                              const inSlip = betslip.some(p => p.key === opt.key + "_" + match.id) || selectedMarket?.key === opt.key;
                              const diff   = getDifficulty(opt.label);
                              const val    = getValueLabel(opt.odds);
                              const pts    = opt.odds ? calcPointsWinCapped(opt.odds, conf, diff.key) : null;
                              return (
                                <div key={oi} style={{ display: "flex", gap: 0, opacity: opt.odds ? 1 : 0.45 }}>
                                  <button
                                    onClick={() => opt.odds ? handleAddToSlip(opt, match.id, match.home + " vs " + match.away, group.category) : null}
                                    disabled={!opt.odds}
                                    style={{ flex: 1, display: "flex", justifyContent: "space-between", alignItems: "center", padding: "10px 12px", borderRadius: opt.odds ? "8px 0 0 8px" : "8px", border: inSlip ? "1.5px solid #f59e0b" : "0.5px solid #1e1e2a", borderRight: opt.odds ? "none" : undefined, background: inSlip ? "#1a1200" : !opt.odds ? "#0c0c10" : "#111118", cursor: opt.odds ? "pointer" : "not-allowed" }}>
                                    <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                                      <span style={{ fontSize: 13, fontWeight: inSlip ? 700 : 400, color: inSlip ? "#f0eff8" : !opt.odds ? "#2a2a3a" : "#b0b0c4" }}>{opt.label}</span>
                                      {pts && !inSlip && opt.odds && <span style={{ fontSize: 10, color: "#22c55e80" }}>+{pts}</span>}
                                    </div>
                                    <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                                      {val && !inSlip && opt.odds && <span style={{ fontSize: 9, color: val.color, fontWeight: 600 }}>{val.label}</span>}
                                      {inSlip && <span style={{ fontSize: 9, color: "#f59e0b", fontWeight: 800 }}>✓</span>}
                                      <div style={{ background: inSlip ? "#f59e0b" : !opt.odds ? "#0e0e14" : "#1e1e2a", borderRadius: 5, padding: "4px 11px", minWidth: 44, textAlign: "center" }}>
                                        {opt.odds
                                          ? <span style={{ fontSize: 14, fontWeight: 900, color: inSlip ? "#000" : "#e0dff0" }}>{opt.odds}</span>
                                          : <span style={{ fontSize: 10, color: "#2a2a3a", fontWeight: 600 }}>N/A</span>
                                        }
                                      </div>
                                    </div>
                                  </button>
                                  {opt.odds && <button onClick={() => setFormulaModal({ opt, diff })} style={{ padding: "0 10px", borderRadius: "0 8px 8px 0", border: inSlip ? "1.5px solid #f59e0b" : "0.5px solid #1e1e2a", borderLeft: "0.5px solid #2a2a3a", background: inSlip ? "#1a1200" : "#0e0e14", cursor: "pointer", color: "#3a3a50", fontSize: 13 }}>ⓘ</button>}
                                </div>
                              );
                            })}
                          </div>
                        )}
                      </div>
                    );
                  })()}
                </div>
              </div>
            )}
          </div>

          {/* ── Prediction Selection Panel ── */}
          {(selectedMarket || betslip.length > 0) && (() => {
            const isAcca       = betslip.length > 1; // single pick = single bet, 2+ = accumulator
            const combinedOdds = isAcca ? parseFloat(betslip.reduce((a,p) => a*(p.odds||2),1).toFixed(2)) : (selectedMarket?.odds || 2);
            const accaBase     = Math.log2(combinedOdds + 1) / Math.log2(3);
            const accaConf     = 0.6 + (conf/100 * 0.4);
            const accaWin      = Math.min(Math.round(50 * accaBase * accaConf * 1.5 * streakMult), 400);
            const accaLoss     = Math.round(3 + (conf/100) * 22); // scales with confidence: 10%→5pts, 90%→23pts
            const totalLegs    = betslip.length;

            return (
              <div style={{ flexShrink: 0, maxHeight: "55%", display: "flex", flexDirection: "column", background: "#0c0c10", borderTop: "1px solid #2a2232" }}>

                {/* Collapsed tab — always visible */}
                <button onClick={() => setSlipOpen(o => !o)} style={{ width: "100%", display: "flex", justifyContent: "space-between", alignItems: "center", padding: "9px 14px", background: "none", border: "none", cursor: "pointer", borderBottom: slipOpen ? "0.5px solid #1e1e28" : "none" }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                    {/* Slip icon with count badge */}
                    <div style={{ position: "relative" }}>
                      <svg width="18" height="18" viewBox="0 0 20 20" fill="none"><rect x="3" y="1" width="14" height="18" rx="2" stroke="#f59e0b" strokeWidth="1.5"/><path d="M6 6h8M6 10h6M6 14h4" stroke="#f59e0b" strokeWidth="1.2" strokeLinecap="round"/></svg>
                      {totalLegs > 0 && <div style={{ position: "absolute", top: -5, right: -5, width: 14, height: 14, borderRadius: "50%", background: "#f59e0b", display: "flex", alignItems: "center", justifyContent: "center" }}><span style={{ fontSize: 8, fontWeight: 900, color: "#000" }}>{totalLegs}</span></div>}
                    </div>
                    <div>
                      {isAcca ? (
                        <span style={{ fontSize: 12, fontWeight: 700, color: "#e0dff0" }}>
                          {totalLegs === 1 ? "Single" : totalLegs === 2 ? "Double" : totalLegs === 3 ? "Treble" : totalLegs + "-Pick Combo"}&nbsp;·&nbsp;
                          <span style={{ color: "#f59e0b", fontWeight: 900 }}>{combinedOdds}</span>
                        </span>
                      ) : (
                        <span style={{ fontSize: 12, fontWeight: 700, color: "#e0dff0" }}>
                          {selectedMarket?.label}&nbsp;·&nbsp;<span style={{ color: "#f59e0b", fontWeight: 900 }}>{selectedMarket?.odds || "—"}</span>
                        </span>
                      )}
                    </div>
                  </div>
                  <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                    <span style={{ fontSize: 12, fontWeight: 800, color: "#22c55e" }}>
                      +{isAcca ? accaWin : pointsToWin} pts
                    </span>
                    <span style={{ fontSize: 10, color: "#4a4958", background: "#1e1e28", padding: "2px 6px", borderRadius: 4 }}>{slipOpen ? "▼" : "▲"}</span>
                  </div>
                </button>

                {/* Expanded slip */}
                {slipOpen && (
                  <div style={{ flex: 1, minHeight: 0, overflowY: "auto", padding: "10px 14px 14px" }}>

                    {/* ── Acca legs — bookmaker style ── */}
                    {isAcca && (
                      <div style={{ marginBottom: 10 }}>
                        {betslip.map((p, i) => (
                          <div key={i} style={{ background: "#111118", border: "0.5px solid #1e1e28", borderRadius: 8, padding: "8px 10px", marginBottom: 5 }}>
                            {/* Match name */}
                            <p style={{ margin: "0 0 3px", fontSize: 10, color: "#4a4958", fontWeight: 600, textTransform: "uppercase", letterSpacing: ".04em" }}>{p.matchLabel}</p>
                            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                              <div>
                                {/* Selection */}
                                <p style={{ margin: 0, fontSize: 13, fontWeight: 700, color: "#e0dff0" }}>{p.label}</p>
                                {/* Market type */}
                                <p style={{ margin: "2px 0 0", fontSize: 10, color: "#4a4958" }}>{p.category || "Match result"}</p>
                              </div>
                              <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                                {/* Odds chip */}
                                <div style={{ background: "#f59e0b", borderRadius: 5, padding: "3px 8px", minWidth: 38, textAlign: "center" }}>
                                  <span style={{ fontSize: 13, fontWeight: 900, color: "#000" }}>{p.odds}</span>
                                </div>
                                {/* Remove */}
                                <button onClick={() => setBetslip(bs => bs.filter((_, j) => j !== i))} style={{ background: "none", border: "0.5px solid #2a2a36", color: "#4a4958", borderRadius: 4, width: 22, height: 22, cursor: "pointer", fontSize: 14, display: "flex", alignItems: "center", justifyContent: "center", fontWeight: 700 }}>×</button>
                              </div>
                            </div>
                          </div>
                        ))}

                        {/* Combined odds row */}
                        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "8px 10px", background: "#1a1508", border: "0.5px solid #f59e0b30", borderRadius: 8, marginTop: 6 }}>
                          <div>
                            <p style={{ margin: 0, fontSize: 10, color: "#4a4958", fontWeight: 700, textTransform: "uppercase", letterSpacing: ".04em" }}>
                              {totalLegs === 1 ? "Single odds" : totalLegs === 2 ? "Double combined odds" : totalLegs === 3 ? "Treble combined odds" : totalLegs + "-Fold combined odds"}
                            </p>
                            {betslip.length > 1 && <p style={{ margin: "2px 0 0", fontSize: 9, color: "#f59e0b" }}>⚡ 1.5x acca bonus applied</p>}
                          </div>
                          <span style={{ fontSize: 22, fontWeight: 900, color: "#f59e0b" }}>{combinedOdds}</span>
                        </div>
                      </div>
                    )}

                    {/* ── Single market (no acca) ── */}
                    {!isAcca && selectedMarket && (
                      <div style={{ background: "#111118", border: "0.5px solid #1e1e28", borderRadius: 8, padding: "8px 10px", marginBottom: 10 }}>
                        <p style={{ margin: "0 0 3px", fontSize: 10, color: "#4a4958", fontWeight: 600, textTransform: "uppercase", letterSpacing: ".04em" }}>{match?.home} vs {match?.away}</p>
                        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                          <p style={{ margin: 0, fontSize: 13, fontWeight: 700, color: "#e0dff0" }}>{selectedMarket.label}</p>
                          <div style={{ background: "#f59e0b", borderRadius: 5, padding: "3px 8px" }}>
                            <span style={{ fontSize: 13, fontWeight: 900, color: "#000" }}>{selectedMarket.odds || "—"}</span>
                          </div>
                        </div>
                      </div>
                    )}

                    {/* ── Confidence slider ── */}
                    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 4 }}>
                      <span style={{ fontSize: 10, color: "#4a4958", textTransform: "uppercase", letterSpacing: ".06em", fontWeight: 700 }}>Confidence</span>
                      <span style={{ fontSize: 16, fontWeight: 900, color: "#6c63ff" }}>{conf}%</span>
                    </div>
                    <input type="range" min={10} max={90} step={10} value={conf} onChange={e => setConf(Number(e.target.value))} style={{ width: "100%", accentColor: "#6c63ff", marginBottom: 10 }} />
                    <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 8 }}>
                      {[10,20,30,40,50,60,70,80,90].map(v => (
                        <span key={v} style={{ fontSize: 9, color: v === conf ? "#6c63ff" : "#2a2a3a", fontWeight: v === conf ? 700 : 400 }}>{v}</span>
                      ))}
                    </div>

                    {/* ── Points payout — aligned ── */}
                    <div style={{ background: "#111118", border: "0.5px solid #1e1e28", borderRadius: 10, padding: "10px 12px", marginBottom: 10 }}>
                      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}>
                        <div style={{ textAlign: "center", flex: 1 }}>
                          <p style={{ margin: "0 0 2px", fontSize: 9, color: "#22c55e80", textTransform: "uppercase", fontWeight: 700, letterSpacing: ".05em" }}>✓ Correct</p>
                          <p style={{ margin: 0, fontSize: 26, fontWeight: 900, color: "#22c55e", lineHeight: 1 }}>+{isAcca ? accaWin : pointsToWin}</p>
                          <p style={{ margin: "2px 0 0", fontSize: 9, color: "#22c55e60" }}>points</p>
                        </div>
                        <div style={{ width: 1, height: 40, background: "#1e1e28" }} />
                        <div style={{ textAlign: "center", flex: 1 }}>
                          <p style={{ margin: "0 0 2px", fontSize: 9, color: "#ef444480", textTransform: "uppercase", fontWeight: 700, letterSpacing: ".05em" }}>✗ Wrong</p>
                          <p style={{ margin: 0, fontSize: 26, fontWeight: 900, color: "#ef4444", lineHeight: 1 }}>-{isAcca ? accaLoss : pointsToLose}</p>
                          <p style={{ margin: "2px 0 0", fontSize: 9, color: "#ef444460" }}>points</p>
                        </div>
                      </div>
                      <div style={{ display: "flex", justifyContent: "space-between", paddingTop: 8, borderTop: "0.5px solid #1e1e28" }}>
                        {!isAcca && pointsBreakdown?.wasCapped && <span style={{ fontSize: 9, color: "#f59e0b" }}>⚠ Capped at {pointsBreakdown.cap}pts</span>}
                        {streakMult > 1 && <span style={{ fontSize: 9, color: "#ef4444" }}>🔥 {streakMult}x streak bonus</span>}
                        <span style={{ fontSize: 9, color: "#4a4958", marginLeft: "auto" }}>Confidence: {conf}% · {isAcca ? "Acca" : (difficulty?.label || "Easy")}</span>
                      </div>
                    </div>

                    {/* ── Notification toggle ── */}
                    <button
                      onClick={async () => {
                        if (!notifyOnPick) {
                          const granted = await requestNotificationPermission();
                          if (granted) setNotifyOnPick(true);
                        } else {
                          setNotifyOnPick(false);
                        }
                      }}
                      style={{ width: "100%", display: "flex", alignItems: "center", justifyContent: "space-between", padding: "9px 12px", marginBottom: 10, borderRadius: 10, border: notifyOnPick ? "0.5px solid #6c63ff44" : "0.5px solid #1e1e28", background: notifyOnPick ? "#6c63ff12" : "#111118", cursor: "pointer" }}>
                      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                        <span style={{ fontSize: 15 }}>{notifyOnPick ? "🔔" : "🔕"}</span>
                        <span style={{ fontSize: 12, color: notifyOnPick ? "#8a83ff" : "#4a4958", fontWeight: 600 }}>Remind me 30 min before kickoff</span>
                      </div>
                      <div style={{ width: 32, height: 18, borderRadius: 9, background: notifyOnPick ? "#6c63ff" : "#2a2a36", display: "flex", alignItems: "center", padding: "0 2px", transition: "background .2s" }}>
                        <div style={{ width: 14, height: 14, borderRadius: "50%", background: "#fff", transform: notifyOnPick ? "translateX(14px)" : "translateX(0)", transition: "transform .2s" }} />
                      </div>
                    </button>

                    {error && <p style={{ fontSize: 12, color: "#ef4444", margin: "0 0 8px" }}>{error}</p>}
                    {slipError && <p style={{ fontSize: 12, color: "#f59e0b", margin: "0 0 8px", background: "#f59e0b15", padding: "6px 10px", borderRadius: 6 }}>⚠ {slipError}</p>}

                    {/* ── Place button ── */}
                    {(() => {
                      const lm = match && findLiveMatch(liveMatches, match.home, match.away, match.fixtureId);
                      if (lm?.isLive || lm?.isFinished) return (
                        <div style={{ width: "100%", padding: "12px", borderRadius: 10, background: "#1e1e28", textAlign: "center" }}>
                          <span style={{ fontSize: 13, color: "#4a4958", fontWeight: 600 }}>
                            {lm.isLive ? `⏱ Match in progress — ${lm.elapsed}' ${lm.homeGoals}–${lm.awayGoals}` : `✅ Match finished — FT ${lm.homeGoals}–${lm.awayGoals}`}
                          </span>
                        </div>
                      );
                      return null;
                    })()}
                    <button
                      onClick={() => {
                        const lm = match && findLiveMatch(liveMatches, match.home, match.away, match.fixtureId);
                        if (lm?.isLive || lm?.isFinished) return;
                        if (isTrialExpired()) { setUpgradePrompt("expired"); return; }
                        isAcca ? submitAcca() : submitPick();
                      }}
                      disabled={loading || (isAcca && totalLegs < 1) || !!(match && findLiveMatch(liveMatches, match.home, match.away, match.fixtureId) && (findLiveMatch(liveMatches, match.home, match.away, match.fixtureId).isLive || findLiveMatch(liveMatches, match.home, match.away, match.fixtureId).isFinished))}
                      style={{ width: "100%", padding: "12px", borderRadius: 10, border: "none", background: loading ? "#1e1e28" : "linear-gradient(135deg, #f59e0b 0%, #f97316 100%)", color: loading ? "#4a4958" : "#000", fontSize: 14, fontWeight: 900, cursor: "pointer", letterSpacing: ".01em" }}>
                      {loading ? "Locking in..." : isAcca
                        ? (totalLegs === 1 ? "Lock In Prediction" : totalLegs === 2 ? "Lock In Double" : totalLegs === 3 ? "Lock In Treble" : "Lock In " + totalLegs + "-Pick Combo")
                        : "Lock In Prediction"}
                    </button>

                    {/* Clear slip */}
                    {isAcca && (
                      <button onClick={() => { setBetslip([]); setSlipOpen(false); }} style={{ width: "100%", marginTop: 6, padding: "7px", background: "none", border: "none", color: "#4a4958", fontSize: 11, cursor: "pointer" }}>
                        Clear slip
                      </button>
                    )}
                  </div>
                )}
              </div>
            );
          })()}
          </div>{/* end middle wrapper */}
          <BottomNav screen={screen} setScreen={id => { if (id === "profile") setViewingProfile(null); setScreen(id); }} nav={NAV} />
        </div>
      )}


      {/* ── Calendar ───────────────────────────────────────── */}
      {screen === "calendar" && (
        <div style={s.screen}>
          <div style={{ ...s.header, background: "linear-gradient(135deg, #1a1230, #0d0d17)", borderBottom: "0.5px solid #2a1f4a" }}>
            <button onClick={() => setScreen("profile")} style={{ background: "none", border: "none", color: "#8a83ff", fontSize: 13, cursor: "pointer", padding: 0, fontWeight: 600 }}>← Back</button>
            <span style={{ ...s.logo, background: "linear-gradient(90deg, #6c63ff, #a855f7)", WebkitBackgroundClip: "text", WebkitTextFillColor: "transparent" }}>Prediction Log</span>
            <span style={{ fontSize: 11, color: "#4a4958" }}>{Object.keys(calendarPicks).length} days</span>
          </div>
          <div style={{ flex: 1, overflowY: "auto", padding: "16px" }}>
            <CalendarView calendarPicks={calendarPicks} profile={profile} />
          </div>
          <BottomNav screen={screen} setScreen={id => { if (id === "leagues") { /* nav handles */ } setScreen(id); }} nav={NAV} />
        </div>
      )}

      {/* ── Done ─────────────────────────────────────────── */}
      {screen === "done" && (
        <div style={{ ...s.screen, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 16, padding: 24 }}>
          <div style={{ width: 64, height: 64, borderRadius: "50%", background: "#22c55e18", border: "1.5px solid #22c55e", display: "flex", alignItems: "center", justifyContent: "center" }}>
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none"><path d="M5 12l5 5L20 7" stroke="#22c55e" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/></svg>
          </div>
          <p style={{ fontSize: 20, fontWeight: 700, color: "#f0eff8", margin: 0 }}>Prediction locked in</p>
          <div style={{ background: "#111116", border: "0.5px solid #1e1e2a", borderRadius: 14, padding: "14px 16px", width: "100%" }}>
            <p style={{ fontSize: 12, color: "#4a4958", margin: "0 0 8px", textTransform: "uppercase", letterSpacing: ".06em", fontWeight: 600 }}>Your slip</p>
            <p style={{ fontSize: 15, fontWeight: 700, color: "#f0eff8", margin: "0 0 2px" }}>{selectedMarket?.label}</p>
            <p style={{ fontSize: 12, color: "#8b8a99", margin: "0 0 12px" }}>{match?.home} vs {match?.away}</p>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8 }}>
              <div style={{ textAlign: "center" }}>
                <p style={{ margin: 0, fontSize: 9, color: "#4a4958", textTransform: "uppercase", letterSpacing: ".05em", fontWeight: 600 }}>Odds</p>
                <p style={{ margin: "3px 0 0", fontSize: 18, fontWeight: 800, color: "#8a83ff" }}>{selectedMarket?.odds || "—"}</p>
              </div>
              <div style={{ textAlign: "center" }}>
                <p style={{ margin: 0, fontSize: 9, color: "#4a4958", textTransform: "uppercase", letterSpacing: ".05em", fontWeight: 600 }}>Conf</p>
                <p style={{ margin: "3px 0 0", fontSize: 18, fontWeight: 800, color: "#6c63ff" }}>{conf}%</p>
              </div>
              <div style={{ textAlign: "center" }}>
                <p style={{ margin: 0, fontSize: 9, color: "#4a4958", textTransform: "uppercase", letterSpacing: ".05em", fontWeight: 600 }}>To win</p>
                <p style={{ margin: "3px 0 0", fontSize: 18, fontWeight: 800, color: "#22c55e" }}>+{pointsToWin}</p>
              </div>
            </div>
          </div>
          <button style={{ ...s.primaryBtn, marginTop: 4 }} onClick={() => setScreen("feed")}>Back to feed</button>
        </div>
      )}
      {/* Upgrade prompt — anonymous user hits a feature gate or trial expires */}
      {upgradePrompt && (
        <div style={{ position: "fixed", inset: 0, background: "#00000095", zIndex: 200, display: "flex", alignItems: "flex-end" }}>
          <div style={{ width: "100%", background: "#141418", borderRadius: "20px 20px 0 0", padding: "24px 20px 40px", border: "0.5px solid #2a2a32" }}>
            <div style={{ width: 36, height: 4, background: "#2a2a32", borderRadius: 2, margin: "0 auto 20px" }} />
            {upgradePrompt === "streak" && <>
              <p style={{ fontSize: 32, textAlign: "center", margin: "0 0 8px" }}>🔥</p>
              <h2 style={{ margin: "0 0 8px", fontSize: 20, fontWeight: 800, color: "#f0eff8", textAlign: "center" }}>
                {profile?.current_streak}-day streak!
              </h2>
              <p style={{ margin: "0 0 6px", fontSize: 13, color: "#8b8a99", textAlign: "center", lineHeight: 1.6 }}>
                You're on a roll, <strong style={{ color: "#f0eff8" }}>{profile?.username}</strong>. Add an email to keep your streak and {profile?.total_points || 0} points — if you don't, they're gone when you leave.
              </p>
            </>}
            {upgradePrompt === "expired" && <>
              <p style={{ fontSize: 32, textAlign: "center", margin: "0 0 8px" }}>⏰</p>
              <h2 style={{ margin: "0 0 8px", fontSize: 20, fontWeight: 800, color: "#f0eff8", textAlign: "center" }}>72-hour trial ended</h2>
              <p style={{ margin: "0 0 6px", fontSize: 13, color: "#8b8a99", textAlign: "center", lineHeight: 1.6 }}>
                Add your email to unlock predictions again and keep your <strong style={{ color: "#f59e0b" }}>{profile?.total_points || 0} points</strong> and <strong style={{ color: "#ef4444" }}>{profile?.current_streak || 0}-day streak</strong>.
              </p>
            </>}
            {upgradePrompt === "social" && <>
              <p style={{ fontSize: 32, textAlign: "center", margin: "0 0 8px" }}>👥</p>
              <h2 style={{ margin: "0 0 8px", fontSize: 20, fontWeight: 800, color: "#f0eff8", textAlign: "center" }}>Follow friends</h2>
              <p style={{ margin: "0 0 6px", fontSize: 13, color: "#8b8a99", textAlign: "center", lineHeight: 1.6 }}>Add an email to follow other predictors and build your rivalry.</p>
            </>}
            {upgradePrompt === "league" && <>
              <p style={{ fontSize: 32, textAlign: "center", margin: "0 0 8px" }}>🏆</p>
              <h2 style={{ margin: "0 0 8px", fontSize: 20, fontWeight: 800, color: "#f0eff8", textAlign: "center" }}>Join a league</h2>
              <p style={{ margin: "0 0 6px", fontSize: 13, color: "#8b8a99", textAlign: "center", lineHeight: 1.6 }}>Add an email to create or join a private league with friends.</p>
            </>}
            {/* Show points/streak summary */}
            {(profile?.total_points > 0 || (profile?.current_streak || 0) > 0) && (
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8, margin: "16px 0" }}>
                <div style={{ background: "#0a1f0a", border: "0.5px solid #22c55e30", borderRadius: 10, padding: "8px", textAlign: "center" }}>
                  <p style={{ margin: 0, fontSize: 18, fontWeight: 900, color: "#22c55e" }}>{profile?.total_points || 0}</p>
                  <p style={{ margin: 0, fontSize: 10, color: "#22c55e80" }}>Points to save</p>
                </div>
                <div style={{ background: "#1f0808", border: "0.5px solid #ef444430", borderRadius: 10, padding: "8px", textAlign: "center" }}>
                  <p style={{ margin: 0, fontSize: 18, fontWeight: 900, color: "#ef4444" }}>{profile?.current_streak || 0}</p>
                  <p style={{ margin: 0, fontSize: 10, color: "#ef444480" }}>Day streak</p>
                </div>
              </div>
            )}
            <button onClick={() => { setUpgradePrompt(null); setEmail(""); setPassword(""); setAuthScreen("upgrade"); }} style={{ width: "100%", padding: "14px", borderRadius: 12, border: "none", background: "linear-gradient(135deg, #22c55e, #16a34a)", color: "#fff", fontSize: 15, fontWeight: 700, cursor: "pointer", marginBottom: 10 }}>
              Save my progress — add email
            </button>
            {upgradePrompt !== "expired" && (
              <button onClick={() => setUpgradePrompt(null)} style={{ width: "100%", padding: "11px", background: "none", border: "none", color: "#4a4958", fontSize: 13, cursor: "pointer" }}>
                Maybe later
              </button>
            )}
          </div>
        </div>
      )}

      {/* Formula modal */}
      {formulaModal && (
        <FormulaModal
          opt={formulaModal.opt}
          diff={formulaModal.diff || getDifficulty(formulaModal.opt?.label || "")}
          currentConf={conf}
          onClose={() => setFormulaModal(null)}
        />
      )}
    </div>
  );
}

// ─── Crest component ─────────────────────────────────────────────
function Crest({ url, size = 24 }) {
  const [err, setErr] = useState(false);
  if (!url || err) {
    return (
      <div style={{ width: size, height: size, borderRadius: 4, background: "#2a2a32", flexShrink: 0 }} />
    );
  }
  return (
    <img
      src={url}
      alt=""
      width={size}
      height={size}
      onError={() => setErr(true)}
      style={{ objectFit: "contain", flexShrink: 0 }}
    />
  );
}

// Shows match string with crests if we have crest data for that match
function MatchWithCrests({ matchStr, matches }) {
  if (!matchStr) return <p style={{ fontSize: 12, color: "#8b8a99", margin: "2px 0 0" }}>{matchStr}</p>;
  const found = matches.find(m => matchStr === m.home + " vs " + m.away);
  if (!found) return <p style={{ fontSize: 12, color: "#8b8a99", margin: "2px 0 0" }}>{matchStr}</p>;
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 5, margin: "3px 0 0" }}>
      <Crest url={found.homeCrest} size={14} />
      <span style={{ fontSize: 12, color: "#8b8a99" }}>{found.home}</span>
      <span style={{ fontSize: 11, color: "#4a4958" }}>vs</span>
      <Crest url={found.awayCrest} size={14} />
      <span style={{ fontSize: 12, color: "#8b8a99" }}>{found.away}</span>
    </div>
  );
}


// ─── Calendar View ────────────────────────────────────────────────
function CalendarView({ calendarPicks, profile }) {
  const [viewDate, setViewDate] = useState(new Date());

  const year  = viewDate.getFullYear();
  const month = viewDate.getMonth();

  const monthName = viewDate.toLocaleDateString("en-GB", { month: "long", year: "numeric" });

  // Build days grid
  const firstDay   = new Date(year, month, 1).getDay(); // 0=Sun
  const startOffset = (firstDay === 0 ? 6 : firstDay - 1); // Mon-start offset
  const daysInMonth = new Date(year, month + 1, 0).getDate();

  const today = new Date();
  const todayKey = today.getFullYear() + "-" + String(today.getMonth() + 1).padStart(2, "0") + "-" + String(today.getDate()).padStart(2, "0");

  const cells = [];
  for (let i = 0; i < startOffset; i++) cells.push(null);
  for (let d = 1; d <= daysInMonth; d++) cells.push(d);

  // Streak stats
  const streak        = profile?.current_streak       || 0;
  const bestStreak    = profile?.best_streak           || 0;
  const dailyStreak   = profile?.daily_streak          || 0;
  const bestDailyStreak = profile?.best_daily_streak   || 0;
  const monthPrefix   = year + "-" + String(month + 1).padStart(2, "0");
  const monthKeys     = Object.keys(calendarPicks).filter(k => k.startsWith(monthPrefix));
  const activeDays    = monthKeys.length;
  const correctDays   = monthKeys.filter(k => calendarPicks[k] === "correct").length;
  const wrongDays     = monthKeys.filter(k => calendarPicks[k] === "wrong").length;

  return (
    <div>
      {/* Streak summary cards */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8, marginBottom: 12 }}>
        <div style={{ background: "linear-gradient(135deg, #0d1a0d, #0f2a0f)", border: "0.5px solid #22c55e40", borderRadius: 12, padding: "12px 10px", textAlign: "center" }}>
          <p style={{ margin: "0 0 1px", fontSize: 26, fontWeight: 900, color: "#22c55e", lineHeight: 1 }}>📅 {dailyStreak}</p>
          <p style={{ margin: 0, fontSize: 9, color: "#22c55e80", textTransform: "uppercase", fontWeight: 700 }}>Daily streak</p>
          <p style={{ margin: "3px 0 0", fontSize: 9, color: "#4a4958" }}>Best: {bestDailyStreak}</p>
        </div>
        <div style={{ background: "linear-gradient(135deg, #1a0a0a, #2a0f0f)", border: "0.5px solid #ef444440", borderRadius: 12, padding: "12px 10px", textAlign: "center" }}>
          <p style={{ margin: "0 0 1px", fontSize: 26, fontWeight: 900, color: "#ef4444", lineHeight: 1 }}>🔥 {streak}</p>
          <p style={{ margin: 0, fontSize: 9, color: "#ef444480", textTransform: "uppercase", fontWeight: 700 }}>Correct streak</p>
          <p style={{ margin: "3px 0 0", fontSize: 9, color: "#4a4958" }}>Best: {bestStreak}</p>
        </div>
      </div>
      {/* This month mini stats */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 6, marginBottom: 16 }}>
        <div style={{ background: "#111116", border: "0.5px solid #1e1e2a", borderRadius: 10, padding: "8px 6px", textAlign: "center" }}>
          <p style={{ margin: 0, fontSize: 16, fontWeight: 800, color: "#f0eff8" }}>{activeDays}</p>
          <p style={{ margin: 0, fontSize: 9, color: "#4a4958", textTransform: "uppercase", fontWeight: 600 }}>Active</p>
        </div>
        <div style={{ background: "#0d1a0d", border: "0.5px solid #22c55e30", borderRadius: 10, padding: "8px 6px", textAlign: "center" }}>
          <p style={{ margin: 0, fontSize: 16, fontWeight: 800, color: "#22c55e" }}>{correctDays}</p>
          <p style={{ margin: 0, fontSize: 9, color: "#22c55e60", textTransform: "uppercase", fontWeight: 600 }}>All correct</p>
        </div>
        <div style={{ background: "#1a0d0d", border: "0.5px solid #ef444430", borderRadius: 10, padding: "8px 6px", textAlign: "center" }}>
          <p style={{ margin: 0, fontSize: 16, fontWeight: 800, color: "#ef4444" }}>{wrongDays}</p>
          <p style={{ margin: 0, fontSize: 9, color: "#ef444460", textTransform: "uppercase", fontWeight: 600 }}>All wrong</p>
        </div>
      </div>

      {/* Month nav */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 14 }}>
        <button onClick={() => setViewDate(new Date(year, month - 1, 1))} style={{ background: "#1a1a2a", border: "0.5px solid #2a2040", borderRadius: 8, color: "#8a83ff", width: 30, height: 30, cursor: "pointer", fontSize: 16, display: "flex", alignItems: "center", justifyContent: "center" }}>‹</button>
        <div style={{ textAlign: "center" }}>
          <p style={{ margin: 0, fontSize: 14, fontWeight: 800, color: "#f0eff8" }}>{monthName}</p>
          <p style={{ margin: 0, fontSize: 10, color: "#4a4958" }}>{activeDays} active day{activeDays !== 1 ? "s" : ""}</p>
        </div>
        <button onClick={() => setViewDate(new Date(year, month + 1, 1))} style={{ background: "#1a1a2a", border: "0.5px solid #2a2040", borderRadius: 8, color: "#8a83ff", width: 30, height: 30, cursor: "pointer", fontSize: 16, display: "flex", alignItems: "center", justifyContent: "center" }}>›</button>
      </div>

      {/* Day headers */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: 3, marginBottom: 4 }}>
        {["M","T","W","T","F","S","S"].map((d, i) => (
          <div key={i} style={{ textAlign: "center", fontSize: 10, fontWeight: 700, color: "#3a3050", padding: "2px 0" }}>{d}</div>
        ))}
      </div>

      {/* Day cells */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: 3 }}>
        {cells.map((d, i) => {
          if (!d) return <div key={i} />;
          const key       = year + "-" + String(month + 1).padStart(2, "0") + "-" + String(d).padStart(2, "0");
          const dayStatus = calendarPicks[key] || null; // "correct"|"wrong"|"mixed"|"pending"|null
          const isToday   = key === todayKey;
          const isPast    = new Date(year, month, d) < today;

          const bgColor = dayStatus === "correct" ? "linear-gradient(135deg, #16a34a, #22c55e)"
            : dayStatus === "wrong"   ? "linear-gradient(135deg, #b91c1c, #ef4444)"
            : dayStatus === "mixed"   ? "linear-gradient(135deg, #b45309, #f59e0b)"
            : dayStatus === "pending" ? "linear-gradient(135deg, #6c63ff, #a855f7)"
            : isToday ? "#1a1a2a" : "transparent";

          const cellIcon = dayStatus === "correct" ? "✓"
            : dayStatus === "wrong"   ? "✗"
            : dayStatus === "mixed"   ? "~"
            : dayStatus === "pending" ? "⏳"
            : null;

          return (
            <div key={i} style={{
              aspectRatio: "1",
              borderRadius: 8,
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              justifyContent: "center",
              background: bgColor,
              border: isToday && !dayStatus ? "1.5px solid #6c63ff" : dayStatus ? "none" : "0.5px solid #1a1a24",
              position: "relative",
              cursor: "default",
            }}>
              <span style={{
                fontSize: 11,
                fontWeight: dayStatus || isToday ? 800 : 400,
                color: dayStatus ? "#fff" : isToday ? "#8a83ff" : isPast ? "#3a3050" : "#6a6080",
                lineHeight: 1,
              }}>{d}</span>
              {cellIcon && (
                <span style={{ fontSize: 7, marginTop: 1, color: "rgba(255,255,255,0.8)", fontWeight: 700 }}>{cellIcon}</span>
              )}
            </div>
          );
        })}
      </div>

      {/* Legend */}
      <div style={{ display: "flex", flexWrap: "wrap", alignItems: "center", gap: 10, marginTop: 16, justifyContent: "center" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 5 }}>
          <div style={{ width: 12, height: 12, borderRadius: 3, background: "linear-gradient(135deg, #16a34a, #22c55e)" }} />
          <span style={{ fontSize: 10, color: "#4a4958" }}>All correct</span>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 5 }}>
          <div style={{ width: 12, height: 12, borderRadius: 3, background: "linear-gradient(135deg, #b91c1c, #ef4444)" }} />
          <span style={{ fontSize: 10, color: "#4a4958" }}>All wrong</span>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 5 }}>
          <div style={{ width: 12, height: 12, borderRadius: 3, background: "linear-gradient(135deg, #b45309, #f59e0b)" }} />
          <span style={{ fontSize: 10, color: "#4a4958" }}>Mixed</span>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 5 }}>
          <div style={{ width: 12, height: 12, borderRadius: 3, background: "linear-gradient(135deg, #6c63ff, #a855f7)" }} />
          <span style={{ fontSize: 10, color: "#4a4958" }}>Pending</span>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 5 }}>
          <div style={{ width: 12, height: 12, borderRadius: 3, border: "0.5px solid #1a1a24" }} />
          <span style={{ fontSize: 10, color: "#4a4958" }}>No pick</span>
        </div>
      </div>

      {/* Motivational message */}
      <div style={{ marginTop: 16, background: "linear-gradient(135deg, #0d0d1a, #130f1f)", border: "0.5px solid #2a2040", borderRadius: 12, padding: "12px 14px", textAlign: "center" }}>
        {dailyStreak === 0 && <p style={{ margin: 0, fontSize: 12, color: "#4a4958" }}>Make a prediction today to start your streak 🎯</p>}
        {dailyStreak === 1 && <p style={{ margin: 0, fontSize: 12, color: "#8a83ff" }}>Day 1 — keep it going tomorrow! 💪</p>}
        {dailyStreak >= 2 && dailyStreak < 7 && <p style={{ margin: 0, fontSize: 12, color: "#f59e0b" }}>🔥 {dailyStreak}-day streak! {7 - dailyStreak} more days for the weekly badge</p>}
        {dailyStreak >= 7 && dailyStreak < 30 && <p style={{ margin: 0, fontSize: 12, color: "#22c55e" }}>⚡ {dailyStreak} days straight! You're unstoppable</p>}
        {dailyStreak >= 30 && <p style={{ margin: 0, fontSize: 12, color: "#a855f7" }}>🏆 {dailyStreak}-day legend. You're in the hall of fame</p>}
      </div>
    </div>
  );
}

// ─── Formula Modal ────────────────────────────────────────────────
function FormulaModal({ opt, diff, currentConf, onClose }) {
  if (!opt || !diff) return null;
  const BASE  = 4;
  const CAPS  = { easy: 2.0, medium: 3.5, hard: 5.0, extreme: 8.0 };
  const cap   = Math.round(BASE * diff.multiplier * (CAPS[diff.key] || 2.0));

  function winPts(conf) {
    const c = conf / 100;
    const cs = 0.6 + c * 0.4;
    return Math.min(Math.round(BASE * diff.multiplier * cs), cap);
  }
  function lossPts(conf) {
    const c = conf / 100;
    const cs = 0.1 + c * 0.25;
    const hardCap = diff.key === "extreme" ? 8 : 99;
    return Math.min(Math.round(BASE * diff.multiplier * cs), hardCap);
  }

  const rows = [10, 20, 30, 40, 50, 60, 70, 80, 90].map(c => ({
    conf: c, win: winPts(c), loss: lossPts(c),
    isCurrent: c === (currentConf || 70),
  }));

  return (
    <div onClick={onClose} style={{ position: "fixed", inset: 0, background: "#00000090", zIndex: 100, display: "flex", alignItems: "flex-end" }}>
      <div onClick={e => e.stopPropagation()} style={{ width: "100%", background: "#141418", borderRadius: "20px 20px 0 0", padding: "20px 18px 36px", border: "0.5px solid #2a2a3a" }}>

        {/* Handle */}
        <div style={{ width: 36, height: 4, background: "#2a2a3a", borderRadius: 2, margin: "0 auto 16px" }} />

        {/* Header */}
        <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 14 }}>
          <div style={{ flex: 1 }}>
            <p style={{ margin: "0 0 2px", fontSize: 11, color: "#4a4958", textTransform: "uppercase", fontWeight: 700, letterSpacing: ".06em" }}>How points work</p>
            <p style={{ margin: 0, fontSize: 15, fontWeight: 800, color: "#e0dff0" }}>{opt.label}</p>
          </div>
          <span style={{ fontSize: 11, fontWeight: 700, padding: "3px 10px", borderRadius: 99, background: diff.color+"22", color: diff.color, border: "0.5px solid "+diff.color+"44" }}>{diff.label}</span>
        </div>

        {/* Formula */}
        <div style={{ background: "#0d0d12", borderRadius: 10, padding: "12px", marginBottom: 14, border: "0.5px solid #1e1e28" }}>
          <p style={{ margin: "0 0 8px", fontSize: 10, color: "#4a4958", fontWeight: 700, textTransform: "uppercase", letterSpacing: ".05em" }}>The formula</p>
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            <div style={{ display: "flex", alignItems: "baseline", gap: 6 }}>
              <span style={{ fontSize: 11, fontWeight: 700, color: "#22c55e", width: 40 }}>✓ Win</span>
              <code style={{ fontSize: 11, color: "#8b8a99", background: "#1a1a22", padding: "3px 8px", borderRadius: 5 }}>4 × {diff.multiplier} × (0.6 + conf × 0.4)</code>
            </div>
            <div style={{ display: "flex", alignItems: "baseline", gap: 6 }}>
              <span style={{ fontSize: 11, fontWeight: 700, color: "#ef4444", width: 40 }}>✗ Loss</span>
              <code style={{ fontSize: 11, color: "#8b8a99", background: "#1a1a22", padding: "3px 8px", borderRadius: 5 }}>4 × {diff.multiplier} × (0.1 + conf × 0.25)</code>
            </div>
          </div>
          <p style={{ margin: "8px 0 0", fontSize: 10, color: "#4a4958" }}>
            Higher confidence → bigger win <span style={{ color: "#ef4444" }}>and</span> bigger loss if wrong. Cap: <span style={{ color: diff.color, fontWeight: 700 }}>+{cap} pts</span> for {diff.label}.
          </p>
        </div>

        {/* Points table at each confidence */}
        <p style={{ margin: "0 0 8px", fontSize: 10, color: "#4a4958", fontWeight: 700, textTransform: "uppercase", letterSpacing: ".05em" }}>Points at each confidence level</p>
        <div style={{ display: "flex", gap: 4, marginBottom: 16 }}>
          {rows.map(r => (
            <div key={r.conf} style={{ flex: 1, background: r.isCurrent ? "#6c63ff18" : "#0d0d12", borderRadius: 6, padding: "6px 2px", textAlign: "center", border: r.isCurrent ? "1.5px solid #6c63ff" : "0.5px solid #1e1e28" }}>
              <p style={{ margin: "0 0 3px", fontSize: 9, color: r.isCurrent ? "#8a83ff" : "#3a3a50", fontWeight: r.isCurrent ? 700 : 400 }}>{r.conf}%</p>
              <p style={{ margin: "0 0 1px", fontSize: 11, fontWeight: 800, color: "#22c55e", lineHeight: 1 }}>+{r.win}</p>
              <p style={{ margin: 0, fontSize: 9, color: "#ef4444" }}>-{r.loss}</p>
            </div>
          ))}
        </div>

        <button onClick={onClose} style={{ width: "100%", padding: "13px", borderRadius: 10, border: "none", background: "#6c63ff", color: "#fff", fontSize: 14, fontWeight: 700, cursor: "pointer" }}>Got it</button>
      </div>
    </div>
  );
}

// ─── Momentum Chart ──────────────────────────────────────────────
function MomentumChart({ picks }) {
  const resolved = picks.filter(p => p.result === "correct" || p.result === "wrong");
  const last10   = resolved.slice(0, 10).reverse(); // oldest first

  if (last10.length < 2) return (
    <p style={{ fontSize: 12, color: "#4a4958", textAlign: "center", padding: "12px 0" }}>
      Need at least 2 resolved picks to show momentum
    </p>
  );

  const W  = 280;
  const H  = 80;
  const PAD = 10;

  // Build cumulative accuracy at each point
  const points = last10.map((p, i) => {
    const slice   = last10.slice(0, i + 1);
    const correct = slice.filter(x => x.result === "correct").length;
    const acc     = correct / slice.length; // 0 to 1
    const x = PAD + (i / (last10.length - 1)) * (W - PAD * 2);
    const y = PAD + (1 - acc) * (H - PAD * 2);
    return { x, y, result: p.result, acc: Math.round(acc * 100), market: p.market };
  });

  // Build SVG path
  const pathD = points.map((p, i) => (i === 0 ? "M" : "L") + p.x + " " + p.y).join(" ");

  // Build area fill path
  const areaD = pathD + " L" + points[points.length - 1].x + " " + (H - PAD) + " L" + PAD + " " + (H - PAD) + " Z";

  // Color based on trend
  const startAcc = points[0].acc;
  const endAcc   = points[points.length - 1].acc;
  const trend    = endAcc - startAcc;
  const lineColor = trend >= 0 ? "#22c55e" : trend > -15 ? "#f59e0b" : "#ef4444";

  return (
    <svg width="100%" viewBox={"0 0 " + W + " " + H} style={{ overflow: "visible" }}>
      {/* Grid lines */}
      {[0.25, 0.5, 0.75].map(level => {
        const y = PAD + (1 - level) * (H - PAD * 2);
        return (
          <line key={level} x1={PAD} y1={y} x2={W - PAD} y2={y}
            stroke="#2a2a32" strokeWidth="0.5" strokeDasharray="3,3" />
        );
      })}
      {/* 50% label */}
      <text x={W - PAD + 3} y={PAD + (H - PAD * 2) * 0.5 + 4} fontSize="8" fill="#4a4958">50%</text>

      {/* Area fill */}
      <path d={areaD} fill={lineColor} fillOpacity="0.08" />

      {/* Line */}
      <path d={pathD} fill="none" stroke={lineColor} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />

      {/* Dots */}
      {points.map((p, i) => (
        <g key={i}>
          <circle cx={p.x} cy={p.y} r="4" fill={p.result === "correct" ? "#22c55e" : "#ef4444"} stroke="#141417" strokeWidth="1.5" />
        </g>
      ))}

      {/* Start / end accuracy labels */}
      <text x={PAD} y={H} fontSize="9" fill="#4a4958">{points[0].acc}%</text>
      <text x={W - PAD} y={H} fontSize="9" fill={lineColor} textAnchor="end" fontWeight="600">{points[points.length - 1].acc}%</text>
    </svg>
  );
}

// ─── Bottom nav ───────────────────────────────────────────────────
function BottomNav({ screen, setScreen, nav }) {
  return (
    <div style={{ flexShrink: 0, background: "#141417", borderTop: "0.5px solid #2a2a32" }}>
      <div style={{ display: "flex" }}>
        {nav.map(n => {
          const on = screen === n.id;
          return (
            <button key={n.id} onClick={() => setScreen(n.id)} style={{ flex: 1, padding: "10px 4px 8px", background: "none", border: "none", cursor: "pointer", display: "flex", flexDirection: "column", alignItems: "center", gap: 3, color: on ? "#8a83ff" : "#4a4958", fontSize: 11, fontWeight: on ? 600 : 400 }}>
              <span style={{ fontSize: 18 }}>{n.icon}</span>
              {n.label}
            </button>
          );
        })}
      </div>
      <div style={{ height: "env(safe-area-inset-bottom)" }} />
    </div>
  );
}

function FeedIcon()    { return <svg width="20" height="20" viewBox="0 0 20 20" fill="none"><path d="M3 5h14M3 10h14M3 15h8" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/></svg>; }
function BoardIcon()   { return <svg width="20" height="20" viewBox="0 0 20 20" fill="none"><path d="M4 15V9M8 15V5M12 15V8M16 15V11" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/></svg>; }
function PlusIcon()    { return <svg width="20" height="20" viewBox="0 0 20 20" fill="none"><circle cx="10" cy="10" r="7" stroke="currentColor" strokeWidth="1.5"/><path d="M10 7v6M7 10h6" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/></svg>; }
function LeagueIcon()  { return <svg width="20" height="20" viewBox="0 0 20 20" fill="none"><path d="M10 2l2 6h6l-5 3.5 2 6L10 14l-5 3.5 2-6L2 8h6z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round"/></svg>; }
function ProfileIcon()  { return <svg width="20" height="20" viewBox="0 0 20 20" fill="none"><circle cx="10" cy="7" r="3" stroke="currentColor" strokeWidth="1.5"/><path d="M4 17c0-3.314 2.686-5 6-5s6 1.686 6 5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/></svg>; }
function CalendarIcon() { return <svg width="20" height="20" viewBox="0 0 20 20" fill="none"><rect x="2" y="3" width="16" height="16" rx="2.5" stroke="currentColor" strokeWidth="1.5"/><path d="M2 8h16M7 2v3M13 2v3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/><circle cx="7" cy="12.5" r="1" fill="currentColor"/><circle cx="10" cy="12.5" r="1" fill="currentColor"/><circle cx="13" cy="12.5" r="1" fill="currentColor"/></svg>; }

function DiffBadge({ d }) {
  const color = d === "hard" ? "#ef4444" : d === "medium" ? "#f59e0b" : "#22c55e";
  return <span style={{ fontSize: 10, fontWeight: 600, padding: "1px 6px", borderRadius: 99, background: color+"20", color }}>{d}</span>;
}

function ResultBadge({ result }) {
  if (!result || result === "pending") return <span style={{ fontSize: 11, color: "#4a4958", display: "block", marginTop: 4 }}>Pending</span>;
  return <span style={{ fontSize: 11, fontWeight: 600, padding: "2px 8px", borderRadius: 99, display: "block", marginTop: 4, background: result==="correct" ? "#22c55e20" : "#ef444420", color: result==="correct" ? "#22c55e" : "#ef4444" }}>{result==="correct" ? "Correct" : "Wrong"}</span>;
}

function Row({ label, value, last }) {
  return (
    <div style={{ display: "flex", justifyContent: "space-between", padding: "8px 0", borderBottom: last ? "none" : "0.5px solid #2a2a32", fontSize: 13 }}>
      <span style={{ color: "#8b8a99" }}>{label}</span>
      <span style={{ color: "#f0eff8", fontWeight: 500 }}>{value}</span>
    </div>
  );
}

const s = {
  root: { position: "fixed", inset: 0, background: "#0f0f18", fontFamily: "'DM Sans', system-ui, sans-serif", display: "flex", flexDirection: "column", paddingTop: "env(safe-area-inset-top)" },
  screen: { flex: 1, minHeight: 0, width: "100%", background: "#0f0f18", display: "flex", flexDirection: "column", overflow: "hidden" },
  header: { display: "flex", alignItems: "center", justifyContent: "space-between", padding: "18px 20px 14px", borderBottom: "0.5px solid #2a2a32", flexShrink: 0 },
  logo:    { fontSize: 18, fontWeight: 700, color: "#f0eff8", letterSpacing: "-.01em" },
  tagline: { fontSize: 12, color: "#4a4958" },
  back:    { background: "none", border: "none", color: "#6c63ff", fontSize: 13, cursor: "pointer", padding: 0 },
  body:    { padding: "20px 20px 32px", flex: 1, overflowY: "auto" },
  section: { padding: "12px 16px 0" },
  sectionLabel: { fontSize: 11, fontWeight: 600, color: "#4a4958", textTransform: "uppercase", letterSpacing: ".07em", marginBottom: 10 },
  card: { background: "#13131c", border: "0.5px solid #2a2040", borderRadius: 12, padding: "12px 14px", marginBottom: 8 },
  cardTitle: { fontSize: 14, fontWeight: 600, color: "#f0eff8", margin: 0 },
  cardSub:   { fontSize: 12, color: "#8b8a99", margin: "2px 0 0" },
  avatar: { width: 24, height: 24, borderRadius: "50%", background: "#6c63ff22", border: "0.5px solid #6c63ff66", color: "#8a83ff", fontSize: 11, fontWeight: 600, display: "flex", alignItems: "center", justifyContent: "center" },
  userName:  { fontSize: 13, fontWeight: 600, color: "#f0eff8" },
  confBadge: { background: "#6c63ff18", color: "#8a83ff", fontSize: 13, fontWeight: 700, padding: "3px 10px", borderRadius: 99, border: "0.5px solid #6c63ff44" },
  fieldLabel: { fontSize: 11, fontWeight: 600, color: "#4a4958", textTransform: "uppercase", letterSpacing: ".07em", marginBottom: 10 },
  input: { width: "100%", padding: "10px 12px", borderRadius: 10, background: "#1a1a1f", border: "0.5px solid #2a2a32", color: "#f0eff8", fontSize: 14, marginBottom: 16, outline: "none" },
  toggle: { display: "flex", background: "#1a1a1f", borderRadius: 10, overflow: "hidden", marginBottom: 16, border: "0.5px solid #2a2a32" },
  toggleBtn: { flex: 1, padding: "9px", border: "none", cursor: "pointer", background: "transparent", color: "#8b8a99", fontSize: 13, fontWeight: 400 },
  toggleBtnOn: { background: "#6c63ff20", color: "#8a83ff", fontWeight: 600 },
  optionBtn: { width: "100%", display: "flex", justifyContent: "space-between", alignItems: "center", padding: "11px 14px", borderRadius: 10, marginBottom: 6, border: "0.5px solid #2a2a32", background: "#1a1a1f", color: "#8b8a99", fontSize: 13, cursor: "pointer", textAlign: "left" },
  optionBtnOn: { border: "0.5px solid #6c63ff", background: "#6c63ff15", color: "#8a83ff" },
  marketBtn: { width: "100%", display: "flex", justifyContent: "space-between", alignItems: "center", padding: "10px 14px", borderRadius: 10, border: "0.5px solid #2a2a32", background: "#1a1a1f", color: "#8b8a99", fontSize: 13, cursor: "pointer", textAlign: "left" },
  marketBtnOn: { border: "0.5px solid #6c63ff", background: "#6c63ff15", color: "#8a83ff" },
  summaryBox: { background: "#1a1a1f", border: "0.5px solid #2a2a32", borderRadius: 12, padding: "4px 14px", marginBottom: 20 },
  primaryBtn: { width: "100%", padding: 13, borderRadius: 12, background: "#6c63ff", color: "#fff", border: "none", fontSize: 14, fontWeight: 600, cursor: "pointer" },
  checkCircle: { width: 64, height: 64, borderRadius: "50%", background: "#22c55e18", border: "1.5px solid #22c55e", display: "flex", alignItems: "center", justifyContent: "center" },
  statCard: { background: "#13131c", borderRadius: 10, border: "0.5px solid #2a2040", padding: "10px 12px" },
  statLabel: { fontSize: 11, color: "#4a4958", margin: "0 0 4px", textTransform: "uppercase", letterSpacing: ".05em" },
  statVal:   { fontSize: 20, fontWeight: 700, margin: 0, color: "#f0eff8" },
  adminSectionTitle: { fontSize: 14, fontWeight: 600, color: "#f0eff8", margin: "0 0 6px" },
  adminBtn: { width: "100%", padding: "11px", borderRadius: 10, background: "#ef444420", border: "0.5px solid #ef444444", color: "#ef4444", fontSize: 13, fontWeight: 600, cursor: "pointer" },
  resolveBtn: { padding: "9px", borderRadius: 8, border: "0.5px solid", fontSize: 13, fontWeight: 600, cursor: "pointer" },
};
