import { useState, useEffect } from "react";
import { supabase } from "./lib/supabase";
import { getDifficulty, calcPointsWin, calcPointsLoss } from "./lib/scoring";

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

export default function App() {
  // Auth
  const [user,        setUser]        = useState(null);
  const [authScreen,  setAuthScreen]  = useState("login");
  const [email,       setEmail]       = useState("");
  const [password,    setPassword]    = useState("");
  const [username,    setUsername]    = useState("");
  const [authError,   setAuthError]   = useState("");
  const [authLoading, setAuthLoading] = useState(false);

  // App
  const [screen,         setScreen]         = useState("feed");
  const [matches,        setMatches]        = useState([]);
  const [matchesLoading, setMatchesLoading] = useState(false);
  const [matchesError,   setMatchesError]   = useState("");
  const [matchSearch,    setMatchSearch]    = useState("");
  const [predictView,    setPredictView]    = useState("list"); // "list" | "detail"
  const [match,          setMatch]          = useState(null);
  const [markets,        setMarkets]        = useState([]);
  const [marketsLoading, setMarketsLoading] = useState(false);
  const [oddsLive,       setOddsLive]       = useState(false);
  const [betslip,        setBetslip]        = useState([]);  // array of picks for accumulator
  const [slipOpen,       setSlipOpen]       = useState(false);
  const [slipMode,       setSlipMode]       = useState("single"); // "single" | "acca"
  const [selectedMarket, setSelectedMarket] = useState(null);
  const [conf,           setConf]           = useState(70);
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
  const [editFavTeam,     setEditFavTeam]     = useState("");
  const [editFavLeague,   setEditFavLeague]   = useState("");
  const [teamSuggestions,   setTeamSuggestions]   = useState([]);
  const [leagueSuggestions, setLeagueSuggestions] = useState([]);
  const [showTeamDrop,      setShowTeamDrop]      = useState(false);
  const [showLeagueDrop,    setShowLeagueDrop]    = useState(false);
  const [editSaving,      setEditSaving]      = useState(false);
  const [editError,       setEditError]       = useState("");

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

  // ── Session ────────────────────────────────────────────────────
  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user ?? null);
    });
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_e, session) => {
      setUser(session?.user ?? null);
    });
    return () => subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (user) { loadFeed(); loadMyPicks(); loadProfile(); }
  }, [user]);

  useEffect(() => {
    if (screen === "predict") { if (matches.length === 0) loadMatches(); setPredictView("list"); setMatchSearch(""); setSelectedMarket(null); setBetslip([]); setSlipOpen(false); setSlipMode("single"); }
    if (screen === "admin")       loadAdminPicks();
    if (screen === "leaderboard") loadLeaderboard(lbTab);
    if (screen === "profile")     loadProfileScreen(viewingProfile);
    if (screen === "leagues")     loadMyLeagues();
  }, [screen]);

  useEffect(() => {
    if (screen === "leaderboard") loadLeaderboard(lbTab);
  }, [lbTab]);

  useEffect(() => {
    if (match) loadOdds(match);
  }, [match]);

  const difficulty      = selectedMarket ? getDifficulty(selectedMarket.label) : null;
  const streakCount     = profile?.current_streak || 0;
  const streakMult      = getStreakMultiplier(streakCount + 1); // +1 because this pick could extend it
  const basePointsToWin = selectedMarket ? calcPointsWin(selectedMarket.odds, conf, difficulty?.multiplier || 1) : 0;
  const pointsToWin     = Math.round(basePointsToWin * streakMult);
  const pointsToLose    = selectedMarket ? calcPointsLoss(conf, difficulty?.multiplier || 1) : 0;

  // ── Profile screen loader ──────────────────────────────────────
  async function openProfile(profileId) {
    setViewingProfile(profileId || null);
    setScreen("profile");
  }

  async function loadProfileScreen(profileId) {
    setProfileLoading(true);
    const targetId = profileId || user.id;

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
    if (profileId && profileId !== user.id) {
      const { data: followData } = await supabase
        .from("follows").select("id")
        .eq("follower_id", user.id)
        .eq("following_id", profileId)
        .single();
      setIsFollowing(!!followData);
    }

    setProfileLoading(false);
  }

  async function handleSaveProfile() {
    if (!editUsername.trim()) { setEditError("Username cannot be empty"); return; }
    // Validate team against matches list
    if (editFavTeam.trim() && matches.length > 0) {
      const allTeams = matches.flatMap(m => [m.home, m.away]);
      if (!allTeams.some(t => t.toLowerCase() === editFavTeam.trim().toLowerCase())) {
        setEditError("Team not found — pick from the suggestions list"); return;
      }
    }
    // Validate league against matches list
    if (editFavLeague.trim() && matches.length > 0) {
      const allLeagues = matches.map(m => m.competition);
      if (!allLeagues.some(l => l.toLowerCase() === editFavLeague.trim().toLowerCase())) {
        setEditError("League not found — pick from the suggestions list"); return;
      }
    }
    setEditSaving(true); setEditError("");
    const { error } = await supabase
      .from("profiles")
      .update({
        username:         editUsername.trim(),
        favourite_team:   editFavTeam.trim()   || null,
        favourite_league: editFavLeague.trim() || null,
      })
      .eq("id", user.id);
    if (error) { setEditError(error.message); }
    else {
      await loadProfile();
      await loadProfileScreen(null);
      setEditMode(false);
    }
    setEditSaving(false);
  }

  async function handleFollow() {
    if (!viewingProfile || viewingProfile === user.id) return;
    setFollowLoading(true);

    if (isFollowing) {
      await supabase.from("follows").delete()
        .eq("follower_id", user.id)
        .eq("following_id", viewingProfile);
      setIsFollowing(false);
      setFollowerCount(c => c - 1);
    } else {
      await supabase.from("follows").insert({
        follower_id:  user.id,
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
      const res  = await fetch("/api/matches");
      const data = await res.json();
      if (data.error) setMatchesError("Could not load matches.");
      else { setMatches(data.matches); setMatch(data.matches[0]); }
    } catch { setMatchesError("Could not load matches."); }
    setMatchesLoading(false);
  }

  async function loadOdds(m) {
    setMarketsLoading(true); setSelectedMarket(null); setMarkets([]); setOddsLive(false);
    try {
      const res  = await fetch("/api/odds?matchHome=" + encodeURIComponent(m.home) + "&matchAway=" + encodeURIComponent(m.away));
      const data = await res.json();
      if (!data.error) { setMarkets(data.markets); setOddsLive(data.live || false); }
    } catch {}
    setMarketsLoading(false);
  }

  async function loadProfile() {
    const { data } = await supabase.from("profiles").select("*").eq("id", user.id).single();
    if (data) setProfile(data);
  }

  async function loadFeed() {
    const { data } = await supabase
      .from("picks").select("*, profiles(username, id)")
      .order("created_at", { ascending: false }).limit(20);
    if (data) setFeed(data);
  }

  async function loadMyPicks() {
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);
    const { data } = await supabase
      .from("picks").select("*").eq("user_id", user.id)
      .gte("created_at", todayStart.toISOString())
      .order("created_at", { ascending: false });
    if (data) setMyPicks(data);
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
    const { data } = await supabase
      .from("picks").select("*, profiles(username)")
      .eq("result", "pending").order("created_at", { ascending: false });
    setAdminPicks(data || []);
    setAdminLoading(false);
  }

  async function resolvePick(pickId, result) {
    setResolvingId(pickId); setAdminMsg({ text: "", ok: true });
    try {
      const res  = await fetch("/api/resolve", {
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
      const res  = await fetch("/api/settle", {
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
      const res  = await fetch("/api/simulate", {
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
    setLeagueLoading(true);
    const { data } = await supabase
      .from("league_members")
      .select("league_id, leagues(id, name, invite_code, creator_id, created_at)")
      .eq("user_id", user.id);
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
    if (!createName.trim()) { setLeagueMsg({ text: "Enter a league name", ok: false }); return; }
    setLeagueActLoading(true); setLeagueMsg({ text: "", ok: true });
    const res  = await fetch("/api/create-league", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: createName, userId: user.id }),
    });
    const data = await res.json();
    if (data.error) { setLeagueMsg({ text: data.error, ok: false }); }
    else {
      setLeagueMsg({ text: "League created!", ok: true });
      setCreateName("");
      await loadMyLeagues();
      setLeagueAction("list");
    }
    setLeagueActLoading(false);
  }

  async function handleJoinLeague() {
    if (!joinCode.trim()) { setLeagueMsg({ text: "Enter an invite code", ok: false }); return; }
    setLeagueActLoading(true); setLeagueMsg({ text: "", ok: true });
    const res  = await fetch("/api/join-league", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ code: joinCode, userId: user.id }),
    });
    const data = await res.json();
    if (data.error) { setLeagueMsg({ text: data.error, ok: false }); }
    else {
      setLeagueMsg({ text: "Joined " + data.league.name + "!", ok: true });
      setJoinCode("");
      await loadMyLeagues();
      setLeagueAction("list");
    }
    setLeagueActLoading(false);
  }

  async function handleLeaveLeague(leagueId) {
    await supabase.from("league_members")
      .delete().eq("league_id", leagueId).eq("user_id", user.id);
    setLeagueView(null);
    await loadMyLeagues();
  }

  function copyCode(code) {
    navigator.clipboard.writeText(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  // ── Auth ───────────────────────────────────────────────────────
  async function handleSignUp() {
    if (!username.trim()) { setAuthError("Please enter a username"); return; }
    setAuthLoading(true); setAuthError("");
    const { data, error } = await supabase.auth.signUp({ email, password });
    if (error) { setAuthError(error.message); setAuthLoading(false); return; }
    const { error: pe } = await supabase.from("profiles").insert({ id: data.user.id, username: username.trim() });
    if (pe) setAuthError(pe.message);
    setAuthLoading(false);
  }

  async function handleLogin() {
    setAuthLoading(true); setAuthError("");
    const { error } = await supabase.auth.signInWithPassword({ email, password });
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
    const diff = getDifficulty(selectedMarket.label);
    const { error } = await supabase.from("picks").insert({
      user_id: user.id, match: `${match.home} vs ${match.away}`,
      market: selectedMarket.label, confidence: conf,
      odds: selectedMarket.odds || null, difficulty: diff.key,
      difficulty_multiplier: diff.multiplier,
      points_possible: pointsToWin, points_lost: pointsToLose, result: "pending",
    });
    if (error) { setError("Failed to save pick."); setLoading(false); return; }
    await loadFeed(); await loadMyPicks();
    setLoading(false); setScreen("done");
  }

  async function submitAcca() {
    if (!betslip.length) return;
    setLoading(true); setError("");
    const diff = getDifficulty(betslip[0].label);
    // Combined odds = multiply all individual odds
    const combinedOdds = parseFloat(betslip.reduce((acc, p) => acc * (p.odds || 2.0), 1).toFixed(2));
    const accaPoints   = Math.round(calcPointsWin(combinedOdds, conf, diff.multiplier) * streakMult * 1.5); // 1.5x acca bonus
    const accaLoss     = Math.round(calcPointsLoss(conf, diff.multiplier) * betslip.length);
    const label        = betslip.map(p => p.label).join(" + ");
    const matchLabel   = betslip.map(p => p.matchLabel).join(" / ");
    const { error } = await supabase.from("picks").insert({
      user_id: user.id,
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
    await loadFeed(); await loadMyPicks();
    setLoading(false); setBetslip([]); setScreen("done");
  }

  // ── Auth screen ────────────────────────────────────────────────
  if (!user) {
    return (
      <div style={s.root}>
        <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&display=swap" rel="stylesheet" />
        <div style={s.screen}>
          <div style={s.header}>
            <span style={s.logo}>Prophit</span>
            <span style={s.tagline}>Predict. Prove it.</span>
          </div>
          <div style={s.body}>
            <div style={s.toggle}>
              {["login","signup"].map(t => (
                <button key={t} onClick={() => { setAuthScreen(t); setAuthError(""); }} style={{ ...s.toggleBtn, ...(authScreen===t ? s.toggleBtnOn : {}) }}>
                  {t === "login" ? "Log in" : "Sign up"}
                </button>
              ))}
            </div>
            {authScreen === "signup" && (<><p style={s.fieldLabel}>Username</p><input type="text" placeholder="e.g. SharpKing" value={username} onChange={e => setUsername(e.target.value)} style={s.input} /></>)}
            <p style={s.fieldLabel}>Email</p>
            <input type="email" placeholder="you@email.com" value={email} onChange={e => setEmail(e.target.value)} style={s.input} />
            <p style={s.fieldLabel}>Password</p>
            <input type="password" placeholder="••••••••" value={password} onChange={e => setPassword(e.target.value)} style={s.input} />
            {authError && <p style={{ fontSize: 13, color: "#ef4444", margin: "0 0 16px" }}>{authError}</p>}
            <button style={{ ...s.primaryBtn, opacity: authLoading ? 0.6 : 1 }} onClick={authScreen === "login" ? handleLogin : handleSignUp} disabled={authLoading}>
              {authLoading ? "Please wait..." : authScreen === "login" ? "Log in" : "Create account"}
            </button>
          </div>
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
            <span style={s.logo}>Predict</span>
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
                  onChange={e => { setSearchQuery(e.target.value); searchUsers(e.target.value); setShowSearch(e.target.value.length > 0); }}
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
                  <div style={s.statCard}><p style={s.statLabel}>Weekly pts</p><p style={{ ...s.statVal, color: "#6c63ff" }}>{profile.weekly_points ?? 0}</p></div>
                  <div style={s.statCard}><p style={s.statLabel}>Total pts</p><p style={{ ...s.statVal, color: "#f0eff8" }}>{profile.total_points ?? 0}</p></div>
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
                <p style={{ ...s.sectionLabel, margin: 0 }}>Today's picks</p>
                <span style={{ fontSize: 11, color: "#4a4958" }}>
                  {new Date().toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" })}
                </span>
              </div>
              {myPicks.length === 0
                ? (
                  <div style={{ background: "#1a1a1f", border: "0.5px solid #2a2a32", borderRadius: 12, padding: "16px 14px", textAlign: "center" }}>
                    <p style={{ fontSize: 22, margin: "0 0 6px" }}>🎯</p>
                    <p style={{ fontSize: 13, fontWeight: 600, color: "#f0eff8", margin: "0 0 4px" }}>No picks yet today</p>
                    <p style={{ fontSize: 12, color: "#4a4958", margin: 0 }}>Head to Predict to make your first pick</p>
                  </div>
                )
                : myPicks.map((p, i) => (
                  <div key={i} style={s.card}>
                    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
                      <div style={{ flex: 1 }}>
                        <div style={{ display: "flex", alignItems: "center", gap: 6, marginBottom: 3 }}>
                          <p style={s.cardTitle}>{p.market}</p>
                          {p.difficulty && <DiffBadge d={p.difficulty} />}
                          {p.streak_multiplier > 1 && <span style={{ fontSize: 10, fontWeight: 600, padding: "1px 5px", borderRadius: 99, background: "#ef444420", color: "#ef4444" }}>{p.streak_multiplier}x</span>}
                        </div>
                        <p style={s.cardSub}>{p.match}</p>
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
                  </div>
                ))
              }
            </section>
            <section style={s.section}>
              <p style={s.sectionLabel}>Community picks</p>
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
      {screen === "profile" && (
        <div style={s.screen}>
          {/* Teal/green header for profile */}
          <div style={s.header}>
            {viewingProfile && viewingProfile !== user.id
              ? <button style={{ ...s.back, color: "#6c63ff" }} onClick={() => setScreen("feed")}>← Back</button>
              : <span style={{ ...s.logo, color: "#f0eff8" }}>Profile</span>
            }
            {viewingProfile && viewingProfile !== user.id
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
                      {/* Fav team autocomplete */}
                      <p style={{ fontSize: 10, color: "#4a4958", textTransform: "uppercase", letterSpacing: ".06em", fontWeight: 600, margin: "0 0 4px", textAlign: "left" }}>Favourite team</p>
                      <div style={{ position: "relative", marginBottom: 10 }}>
                        <input type="text" placeholder="Type to search teams..." value={editFavTeam}
                          onChange={e => {
                            const v = e.target.value;
                            setEditFavTeam(v);
                            if (v.length > 0) {
                              const allTeams = [...new Set(matches.flatMap(m => [m.home, m.away]))].sort();
                              const sugg = allTeams.filter(t => t.toLowerCase().includes(v.toLowerCase()));
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
                              <button key={i} onMouseDown={() => { setEditFavTeam(t); setShowTeamDrop(false); }} style={{ width: "100%", padding: "9px 14px", background: "none", border: "none", textAlign: "left", color: "#f0eff8", fontSize: 13, cursor: "pointer", borderBottom: i < teamSuggestions.length - 1 ? "0.5px solid #2a2a32" : "none" }}>
                                {t}
                              </button>
                            ))}
                          </div>
                        )}
                      </div>

                      {/* Fav league autocomplete */}
                      <p style={{ fontSize: 10, color: "#4a4958", textTransform: "uppercase", letterSpacing: ".06em", fontWeight: 600, margin: "0 0 4px", textAlign: "left" }}>Favourite league</p>
                      <div style={{ position: "relative", marginBottom: 10 }}>
                        <input type="text" placeholder="Type to search leagues..." value={editFavLeague}
                          onChange={e => {
                            const v = e.target.value;
                            setEditFavLeague(v);
                            if (v.length > 0) {
                              const allLeagues = [...new Set(matches.map(m => m.competition))].sort();
                              const sugg = allLeagues.filter(l => l.toLowerCase().includes(v.toLowerCase()));
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
                              <button key={i} onMouseDown={() => { setEditFavLeague(l); setShowLeagueDrop(false); }} style={{ width: "100%", padding: "9px 14px", background: "none", border: "none", textAlign: "left", color: "#f0eff8", fontSize: 13, cursor: "pointer", borderBottom: i < leagueSuggestions.length - 1 ? "0.5px solid #2a2a32" : "none" }}>
                                {l}
                              </button>
                            ))}
                          </div>
                        )}
                      </div>
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
                        {profileData.favourite_team && (
                          <span style={{ fontSize: 11, background: "#6c63ff20", color: "#8a83ff", padding: "2px 8px", borderRadius: 4, fontWeight: 500 }}>⚽ {profileData.favourite_team}</span>
                        )}
                        {profileData.favourite_league && (
                          <span style={{ fontSize: 11, background: "#f59e0b20", color: "#f59e0b", padding: "2px 8px", borderRadius: 4, fontWeight: 500 }}>🏆 {profileData.favourite_league}</span>
                        )}
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
                  {(!viewingProfile || viewingProfile === user.id) && !editMode && (
                    <button onClick={() => { setEditUsername(profileData.username || ""); setEditFavTeam(profileData.favourite_team || ""); setEditFavLeague(profileData.favourite_league || ""); setEditMode(true); setEditError(""); if (matches.length === 0) loadMatches(); }} style={{ marginBottom: 8, padding: "6px 18px", borderRadius: 99, border: "0.5px solid #2a2a32", background: "transparent", color: "#8b8a99", fontSize: 12, cursor: "pointer" }}>
                      Edit profile
                    </button>
                  )}

                  {/* Follow button — other users only */}
                  {viewingProfile && viewingProfile !== user.id && (
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
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8, padding: "16px 16px 0" }}>
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
                </div>

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

                {/* Accuracy */}
                {profilePicks.length > 0 && (() => {
                  const resolved = profilePicks.filter(p => p.result !== "pending");
                  const correct  = profilePicks.filter(p => p.result === "correct").length;
                  const accuracy = resolved.length > 0 ? Math.round((correct / resolved.length) * 100) : null;
                  return accuracy != null ? (
                    <div style={{ padding: "8px 16px 0" }}>
                      <div style={{ ...s.statCard }}>
                        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                          <div>
                            <p style={{ fontSize: 11, color: "#4a4958", margin: "0 0 4px", textTransform: "uppercase", letterSpacing: ".05em" }}>Accuracy</p>
                            <p style={{ fontSize: 20, fontWeight: 700, margin: 0, color: accuracy >= 60 ? "#22c55e" : accuracy >= 40 ? "#f59e0b" : "#ef4444" }}>{accuracy}%</p>
                          </div>
                          <div style={{ textAlign: "right" }}>
                            <p style={{ fontSize: 11, color: "#4a4958", margin: "0 0 4px", textTransform: "uppercase", letterSpacing: ".05em" }}>Record</p>
                            <p style={{ fontSize: 14, fontWeight: 600, color: "#f0eff8", margin: 0 }}>{correct}W – {resolved.length - correct}L</p>
                          </div>
                        </div>
                        <div style={{ background: "#2a2a32", borderRadius: 4, height: 6, overflow: "hidden", marginTop: 10 }}>
                          <div style={{ width: accuracy + "%", height: "100%", background: accuracy >= 60 ? "#22c55e" : accuracy >= 40 ? "#f59e0b" : "#ef4444", borderRadius: 4, transition: "width .3s" }} />
                        </div>
                      </div>
                    </div>
                  ) : null;
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

          {!viewingProfile || viewingProfile === user.id
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
          <div style={{ flex: 1, overflowY: "auto" }}>
            <div style={{ padding: "12px 16px 0" }}>
              <div style={s.toggle}>
                {["weekly","alltime"].map(t => (
                  <button key={t} onClick={() => setLbTab(t)} style={{ ...s.toggleBtn, ...(lbTab===t ? s.toggleBtnOn : {}) }}>
                    {t === "weekly" ? "This week" : "All time"}
                  </button>
                ))}
              </div>
              {lbLoading && <p style={{ fontSize: 13, color: "#4a4958", padding: "8px 0" }}>Loading...</p>}
              {!lbLoading && lbData.length === 0 && <p style={{ fontSize: 13, color: "#4a4958", padding: "8px 0" }}>No data yet — make some picks!</p>}
              {!lbLoading && lbData.map((p, i) => {
                const isMe   = p.id === user.id;
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
                            <div style={{ width: 28, height: 28, borderRadius: "50%", background: p.id === user.id ? "#6c63ff22" : "#2a2a32", border: "0.5px solid " + (p.id === user.id ? "#6c63ff66" : "#3a3a42"), color: p.id === user.id ? "#8a83ff" : "#8b8a99", fontSize: 11, fontWeight: 600, display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
                              {p.username?.[0]?.toUpperCase() ?? "?"}
                            </div>

                            {/* Name */}
                            <div style={{ flex: 1 }}>
                              <p style={{ margin: 0, fontSize: 13, fontWeight: 600, color: p.id === user.id ? "#8a83ff" : "#f0eff8" }}>
                                {p.username}
                                {p.id === user.id && <span style={{ fontSize: 10, color: "#6c63ff", marginLeft: 5 }}>you</span>}
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
      {screen === "leagues" && (
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
                  const isMe   = m.id === user.id;
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

                {/* Leave league */}
                {leagueView.creator_id !== user.id && (
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
        <div style={{ ...s.screen, background: "#0a0a0e" }}>

          {/* Header */}
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "14px 16px 10px", borderBottom: "0.5px solid #1e1e2a", background: "#0d0d12", flexShrink: 0 }}>
            <button style={s.back} onClick={() => { setScreen("feed"); setBetslip([]); setSelectedMarket(null); setMarkets([]); setPredictView("list"); }}>← Back</button>
            <span style={{ fontSize: 15, fontWeight: 800, color: "#f0eff8", letterSpacing: "-.01em" }}>
              {predictView === "detail" && match ? match.home + " vs " + match.away : "Predictions"}
            </span>
            {/* Betslip tab */}
            <button onClick={() => { setSlipOpen(o => !o); }} style={{ position: "relative", background: betslip.length > 0 ? "#f59e0b" : "#1e1e2a", border: "none", borderRadius: 8, padding: "5px 10px", cursor: "pointer", display: "flex", alignItems: "center", gap: 5 }}>
              <svg width="14" height="14" viewBox="0 0 20 20" fill="none"><rect x="3" y="2" width="14" height="16" rx="2" stroke={betslip.length > 0 ? "#000" : "#8a83ff"} strokeWidth="1.5"/><path d="M7 7h6M7 11h4" stroke={betslip.length > 0 ? "#000" : "#8a83ff"} strokeWidth="1.5" strokeLinecap="round"/></svg>
              <span style={{ fontSize: 12, fontWeight: 800, color: betslip.length > 0 ? "#000" : "#8a83ff" }}>
                {betslip.length > 0 ? betslip.length + " slip" : "Slip"}
              </span>
            </button>
          </div>

          {/* Mode tabs */}
          <div style={{ display: "flex", background: "#0d0d12", borderBottom: "0.5px solid #1e1e2a", flexShrink: 0 }}>
            {[{ id: "single", label: "Single" }, { id: "acca", label: "Accumulator" }].map(t => (
              <button key={t.id} onClick={() => { setSlipMode(t.id); if (t.id === "single") { setBetslip([]); } setSelectedMarket(null); }} style={{ flex: 1, padding: "9px 4px", border: "none", background: "none", cursor: "pointer", fontSize: 12, fontWeight: slipMode === t.id ? 700 : 400, color: slipMode === t.id ? "#f59e0b" : "#4a4958", borderBottom: slipMode === t.id ? "2px solid #f59e0b" : "2px solid transparent" }}>{t.label}</button>
            ))}
          </div>

          {/* Content area */}
          <div style={{ flex: 1, overflowY: "auto", paddingBottom: (betslip.length > 0 || selectedMarket) ? 150 : 16 }}>

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
              const q         = matchSearch.toLowerCase().trim();
              const favTeam   = (profile?.favourite_team   || "").toLowerCase();
              const favLeague = (profile?.favourite_league || "").toLowerCase();
              const filtered  = q ? matches.filter(m => m.home.toLowerCase().includes(q) || m.away.toLowerCase().includes(q) || m.competition.toLowerCase().includes(q)) : matches;

              const grouped = {};
              filtered.forEach(m => { if (!grouped[m.competition]) grouped[m.competition] = []; grouped[m.competition].push(m); });
              const entries = Object.entries(grouped);
              entries.sort(([a], [b]) => {
                const aF = favLeague && a.toLowerCase().includes(favLeague);
                const bF = favLeague && b.toLowerCase().includes(favLeague);
                if (aF && !bF) return -1; if (!aF && bF) return 1; return 0;
              });
              entries.forEach(([, ms]) => {
                if (!favTeam) return;
                ms.sort((a, b) => {
                  const aF = a.home.toLowerCase().includes(favTeam) || a.away.toLowerCase().includes(favTeam);
                  const bF = b.home.toLowerCase().includes(favTeam) || b.away.toLowerCase().includes(favTeam);
                  if (aF && !bF) return -1; if (!aF && bF) return 1; return 0;
                });
              });

              return (
                <div style={{ padding: "10px 12px 0" }}>
                  {/* Search */}
                  <div style={{ display: "flex", alignItems: "center", gap: 8, background: "#141418", border: "0.5px solid #1e1e2a", borderRadius: 8, padding: "8px 12px", marginBottom: 12 }}>
                    <svg width="13" height="13" viewBox="0 0 20 20" fill="none"><circle cx="9" cy="9" r="6" stroke="#4a4958" strokeWidth="1.5"/><path d="M13.5 13.5L17 17" stroke="#4a4958" strokeWidth="1.5" strokeLinecap="round"/></svg>
                    <input type="text" placeholder="Search team or league..." value={matchSearch} onChange={e => setMatchSearch(e.target.value)} style={{ background: "none", border: "none", outline: "none", color: "#f0eff8", fontSize: 13, flex: 1 }} />
                    {matchSearch && <button onClick={() => setMatchSearch("")} style={{ background: "none", border: "none", color: "#4a4958", cursor: "pointer", padding: 0, fontSize: 16 }}>×</button>}
                  </div>

                  {matchesLoading && <p style={{ fontSize: 13, color: "#4a4958", textAlign: "center", padding: "20px 0" }}>Loading fixtures...</p>}

                  {entries.map(([comp, compMatches]) => {
                    const isFavLeague = favLeague && comp.toLowerCase().includes(favLeague);
                    return (
                      <div key={comp} style={{ marginBottom: 16 }}>
                        {/* League header */}
                        <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "6px 4px", borderBottom: "0.5px solid #1e1e2a", marginBottom: 6 }}>
                          <span style={{ fontSize: 10, fontWeight: 800, color: isFavLeague ? "#f59e0b" : "#4a4958", textTransform: "uppercase", letterSpacing: ".08em", flex: 1 }}>
                            {isFavLeague ? "⭐ " : ""}{comp}
                          </span>
                          <span style={{ fontSize: 9, color: "#2a2a32", fontWeight: 600 }}>H&nbsp;&nbsp;&nbsp;D&nbsp;&nbsp;&nbsp;A</span>
                        </div>

                        {/* Match rows — Bet365 style */}
                        {compMatches.map(m => {
                          const isActive = match?.id === m.id;
                          const isFavMatch = favTeam && (m.home.toLowerCase().includes(favTeam) || m.away.toLowerCase().includes(favTeam));
                          // Try to find quick h2h odds from loaded markets if this match is selected
                          const h2hOdds = isActive && markets.length > 0
                            ? markets.find(g => g.category === "Match result")?.options
                            : null;

                          return (
                            <div key={m.id} style={{ background: isActive ? "#141420" : "#0e0e14", border: isActive ? "0.5px solid #6c63ff44" : "0.5px solid #1a1a24", borderRadius: 8, marginBottom: 5, overflow: "hidden" }}>
                              {/* Match info row */}
                              <button onClick={() => { setMatch(m); setPredictView("detail"); loadOdds(m); setSelectedMarket(null); }} style={{ width: "100%", display: "flex", alignItems: "center", padding: "8px 10px", background: "none", border: "none", cursor: "pointer", textAlign: "left", gap: 8 }}>
                                {isFavMatch && <span style={{ fontSize: 9, color: "#f59e0b" }}>★</span>}
                                <div style={{ flex: 1, minWidth: 0 }}>
                                  <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                                    <Crest url={m.homeCrest} size={16} />
                                    <span style={{ fontSize: 12, fontWeight: 600, color: "#e0dff0", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{m.home}</span>
                                  </div>
                                  <div style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 3 }}>
                                    <Crest url={m.awayCrest} size={16} />
                                    <span style={{ fontSize: 12, fontWeight: 600, color: "#e0dff0", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{m.away}</span>
                                  </div>
                                  <span style={{ fontSize: 10, color: "#4a4958", display: "block", marginTop: 2 }}>{m.time}</span>
                                </div>
                                {/* Quick H2H odds buttons inline */}
                                <div style={{ display: "flex", gap: 4, flexShrink: 0 }}>
                                  {h2hOdds ? h2hOdds.map((opt, oi) => {
                                    const inSlip = slipMode === "acca" ? betslip.some(p => p.key === opt.key + "_" + m.id) : selectedMarket?.key === opt.key;
                                    return (
                                      <button key={oi} onClick={e => {
                                        e.stopPropagation();
                                        if (slipMode === "single") {
                                          setSelectedMarket(opt); setSlipOpen(true);
                                        } else {
                                          // Acca: toggle this pick
                                          const slipKey = opt.key + "_" + m.id;
                                          if (betslip.some(p => p.key === slipKey)) {
                                            setBetslip(bs => bs.filter(p => p.key !== slipKey));
                                          } else {
                                            setBetslip(bs => [...bs, { ...opt, key: slipKey, matchLabel: m.home + " vs " + m.away, matchId: m.id }]);
                                          }
                                        }
                                      }} style={{ minWidth: 44, padding: "5px 4px", borderRadius: 6, border: inSlip ? "1.5px solid #f59e0b" : "0.5px solid #2a2a32", background: inSlip ? "#f59e0b20" : "#1a1a24", cursor: "pointer", textAlign: "center" }}>
                                        <p style={{ margin: 0, fontSize: 9, color: "#4a4958", fontWeight: 600 }}>{["H","D","A"][oi]}</p>
                                        <p style={{ margin: 0, fontSize: 12, fontWeight: 800, color: inSlip ? "#f59e0b" : "#c8c7d4" }}>{opt.odds || "—"}</p>
                                      </button>
                                    );
                                  }) : [0,1,2].map(i => (
                                    <div key={i} style={{ minWidth: 44, padding: "5px 4px", borderRadius: 6, border: "0.5px solid #1a1a24", background: "#141418", textAlign: "center" }}>
                                      <p style={{ margin: 0, fontSize: 9, color: "#2a2a32", fontWeight: 600 }}>{["H","D","A"][i]}</p>
                                      <p style={{ margin: 0, fontSize: 11, color: "#2a2a32" }}>—</p>
                                    </div>
                                  ))}
                                </div>
                                <span style={{ fontSize: 11, color: "#3a3a48", marginLeft: 4 }}>›</span>
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

            {/* Detail view — full markets when match tapped */}
            {predictView === "detail" && match && (
              <div style={{ padding: "10px 12px 0" }}>
                {/* Back to list */}
                <button onClick={() => { setPredictView("list"); setSelectedMarket(null); setMarkets([]); }} style={{ display: "flex", alignItems: "center", gap: 4, background: "none", border: "none", color: "#8a83ff", fontSize: 12, cursor: "pointer", padding: "0 0 10px", fontWeight: 600 }}>
                  ← All matches
                </button>

                {/* Live odds badge */}
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 10 }}>
                  <span style={{ fontSize: 11, color: "#4a4958" }}>{match.time}</span>
                  {oddsLive
                    ? <span style={{ fontSize: 10, fontWeight: 700, padding: "2px 8px", borderRadius: 99, background: "#22c55e20", border: "0.5px solid #22c55e", color: "#22c55e", letterSpacing: ".04em" }}>● LIVE ODDS</span>
                    : <span style={{ fontSize: 10, fontWeight: 700, padding: "2px 8px", borderRadius: 99, background: "#1e1e2a", color: "#4a4958", letterSpacing: ".04em" }}>EST. ODDS</span>
                  }
                </div>

                {marketsLoading && <p style={{ fontSize: 13, color: "#4a4958", textAlign: "center", padding: "20px 0" }}>Loading odds...</p>}

                {!marketsLoading && markets.map((group, gi) => (
                  <div key={gi} style={{ marginBottom: 14 }}>
                    <p style={{ fontSize: 10, fontWeight: 800, color: "#4a4958", textTransform: "uppercase", letterSpacing: ".08em", margin: "0 0 6px", padding: "0 2px" }}>{group.category}</p>
                    {/* Match result as 3 big buttons */}
                    {group.category === "Match result" ? (
                      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 5 }}>
                        {group.options.map((opt, oi) => {
                          const inSlip = slipMode === "single" ? selectedMarket?.key === opt.key : betslip.some(p => p.key === opt.key + "_" + match.id);
                          return (
                            <button key={oi} onClick={() => {
                              if (slipMode === "single") { setSelectedMarket(opt); setSlipOpen(true); }
                              else {
                                const slipKey = opt.key + "_" + match.id;
                                if (betslip.some(p => p.key === slipKey)) { setBetslip(bs => bs.filter(p => p.key !== slipKey)); }
                                else { setBetslip(bs => [...bs, { ...opt, key: slipKey, matchLabel: match.home + " vs " + match.away, matchId: match.id }]); }
                              }
                            }} style={{ padding: "10px 4px", borderRadius: 8, border: inSlip ? "1.5px solid #f59e0b" : "0.5px solid #1e1e2a", background: inSlip ? "#f59e0b15" : "#141418", cursor: "pointer", textAlign: "center" }}>
                              <p style={{ margin: "0 0 4px", fontSize: 10, color: inSlip ? "#f59e0b" : "#6a6a80", fontWeight: 700, textTransform: "uppercase" }}>{opt.label.replace(" win","").replace("Win","")}</p>
                              <p style={{ margin: 0, fontSize: 18, fontWeight: 800, color: inSlip ? "#f59e0b" : "#e0dff0" }}>{opt.odds || "—"}</p>
                              {inSlip && <p style={{ margin: "3px 0 0", fontSize: 9, color: "#f59e0b", fontWeight: 700 }}>✓ ADDED</p>}
                            </button>
                          );
                        })}
                      </div>
                    ) : (
                      <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
                        {group.options.map((opt, oi) => {
                          const inSlip = slipMode === "single" ? selectedMarket?.key === opt.key : betslip.some(p => p.key === opt.key + "_" + match.id);
                          const diff   = getDifficulty(opt.label);
                          return (
                            <button key={oi} onClick={() => {
                              if (slipMode === "single") { setSelectedMarket(opt); setSlipOpen(true); }
                              else {
                                const slipKey = opt.key + "_" + match.id;
                                if (betslip.some(p => p.key === slipKey)) { setBetslip(bs => bs.filter(p => p.key !== slipKey)); }
                                else { setBetslip(bs => [...bs, { ...opt, key: slipKey, matchLabel: match.home + " vs " + match.away, matchId: match.id }]); }
                              }
                            }} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "9px 12px", borderRadius: 7, border: inSlip ? "1.5px solid #f59e0b" : "0.5px solid #1e1e2a", background: inSlip ? "#f59e0b10" : "#141418", cursor: "pointer" }}>
                              <div style={{ display: "flex", alignItems: "center", gap: 7 }}>
                                <span style={{ fontSize: 12, fontWeight: inSlip ? 700 : 400, color: inSlip ? "#e0dff0" : "#a0a0b8" }}>{opt.label}</span>
                                <span style={{ fontSize: 9, fontWeight: 700, padding: "1px 5px", borderRadius: 4, background: diff.color + "18", color: diff.color }}>{diff.label.toUpperCase()}</span>
                              </div>
                              <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                                {inSlip && <span style={{ fontSize: 9, color: "#f59e0b", fontWeight: 800 }}>✓</span>}
                                <span style={{ fontSize: 14, fontWeight: 800, color: inSlip ? "#f59e0b" : "#e0dff0", background: inSlip ? "#f59e0b20" : "#1e1e2a", padding: "3px 10px", borderRadius: 6, minWidth: 44, textAlign: "center" }}>{opt.odds || "—"}</span>
                              </div>
                            </button>
                          );
                        })}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* ── Betslip drawer ── */}
          {(selectedMarket || betslip.length > 0) && (
            <div style={{ position: "absolute", bottom: 0, left: 0, right: 0, background: "#0d0d12", borderTop: "1px solid #f59e0b44", zIndex: 20, borderRadius: "0 0 24px 24px" }}>
              {/* Slip header */}
              <button onClick={() => setSlipOpen(o => !o)} style={{ width: "100%", display: "flex", justifyContent: "space-between", alignItems: "center", padding: "10px 16px", background: "none", border: "none", cursor: "pointer" }}>
                <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                  <div style={{ width: 8, height: 8, borderRadius: "50%", background: "#f59e0b", boxShadow: "0 0 8px #f59e0b" }} />
                  {slipMode === "single" && selectedMarket && (
                    <span style={{ fontSize: 13, fontWeight: 700, color: "#f0eff8" }}>{selectedMarket.label} · <span style={{ color: "#f59e0b" }}>{selectedMarket.odds}</span></span>
                  )}
                  {slipMode === "acca" && betslip.length > 0 && (
                    <span style={{ fontSize: 13, fontWeight: 700, color: "#f0eff8" }}>
                      {betslip.length} pick acca · <span style={{ color: "#f59e0b" }}>{parseFloat(betslip.reduce((a,p) => a*(p.odds||2),1).toFixed(2))}x odds</span>
                    </span>
                  )}
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                  <span style={{ fontSize: 12, fontWeight: 700, color: "#22c55e" }}>+{slipMode === "single" ? pointsToWin : Math.round(calcPointsWin(parseFloat(betslip.reduce((a,p)=>a*(p.odds||2),1).toFixed(2)), conf, 1) * streakMult * 1.5)} pts</span>
                  <span style={{ fontSize: 11, color: "#4a4958" }}>{slipOpen ? "▼" : "▲"}</span>
                </div>
              </button>

              {slipOpen && (
                <div style={{ padding: "0 16px 16px" }}>

                  {/* Acca picks list */}
                  {slipMode === "acca" && betslip.length > 0 && (
                    <div style={{ background: "#111116", borderRadius: 10, padding: "8px 10px", marginBottom: 10, border: "0.5px solid #1e1e2a" }}>
                      {betslip.map((p, i) => (
                        <div key={i} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "5px 0", borderBottom: i < betslip.length - 1 ? "0.5px solid #1e1e2a" : "none" }}>
                          <div>
                            <p style={{ margin: 0, fontSize: 12, fontWeight: 600, color: "#e0dff0" }}>{p.label}</p>
                            <p style={{ margin: 0, fontSize: 10, color: "#4a4958" }}>{p.matchLabel}</p>
                          </div>
                          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                            <span style={{ fontSize: 13, fontWeight: 800, color: "#f59e0b" }}>{p.odds}</span>
                            <button onClick={() => setBetslip(bs => bs.filter((_, j) => j !== i))} style={{ background: "#ef444420", border: "none", color: "#ef4444", borderRadius: 4, width: 20, height: 20, cursor: "pointer", fontSize: 12, display: "flex", alignItems: "center", justifyContent: "center" }}>×</button>
                          </div>
                        </div>
                      ))}
                      <div style={{ display: "flex", justifyContent: "space-between", marginTop: 8, paddingTop: 8, borderTop: "0.5px solid #f59e0b30" }}>
                        <span style={{ fontSize: 11, fontWeight: 700, color: "#f59e0b" }}>Combined odds</span>
                        <span style={{ fontSize: 16, fontWeight: 900, color: "#f59e0b" }}>{parseFloat(betslip.reduce((a,p) => a*(p.odds||2),1).toFixed(2))}</span>
                      </div>
                    </div>
                  )}

                  {/* Confidence */}
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 5 }}>
                    <span style={{ fontSize: 10, color: "#4a4958", textTransform: "uppercase", letterSpacing: ".06em", fontWeight: 700 }}>Confidence</span>
                    <span style={{ fontSize: 18, fontWeight: 900, color: "#6c63ff" }}>{conf}%</span>
                  </div>
                  <input type="range" min={10} max={99} step={1} value={conf} onChange={e => setConf(Number(e.target.value))} style={{ width: "100%", accentColor: "#6c63ff", marginBottom: 10 }} />

                  {/* Points preview */}
                  <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8, marginBottom: 10 }}>
                    <div style={{ background: "#0a1f0a", border: "0.5px solid #22c55e30", borderRadius: 8, padding: "7px 10px" }}>
                      <p style={{ margin: 0, fontSize: 9, color: "#22c55e80", textTransform: "uppercase", fontWeight: 700 }}>Win</p>
                      <p style={{ margin: "2px 0 0", fontSize: 18, fontWeight: 900, color: "#22c55e" }}>
                        +{slipMode === "single" ? pointsToWin : Math.round(calcPointsWin(parseFloat(betslip.reduce((a,p)=>a*(p.odds||2),1).toFixed(2)), conf, 1) * streakMult * 1.5)}
                      </p>
                      {slipMode === "acca" && betslip.length > 1 && <p style={{ margin: "2px 0 0", fontSize: 9, color: "#f59e0b" }}>⚡ 1.5x acca bonus</p>}
                      {streakMult > 1 && <p style={{ margin: "2px 0 0", fontSize: 9, color: "#ef4444" }}>🔥 {streakMult}x streak</p>}
                    </div>
                    <div style={{ background: "#1f0a0a", border: "0.5px solid #ef444430", borderRadius: 8, padding: "7px 10px" }}>
                      <p style={{ margin: 0, fontSize: 9, color: "#ef444480", textTransform: "uppercase", fontWeight: 700 }}>Risk</p>
                      <p style={{ margin: "2px 0 0", fontSize: 18, fontWeight: 900, color: "#ef4444" }}>
                        -{slipMode === "single" ? pointsToLose : Math.round(calcPointsLoss(conf, 1) * Math.max(betslip.length, 1))}
                      </p>
                    </div>
                  </div>

                  {error && <p style={{ fontSize: 12, color: "#ef4444", margin: "0 0 8px" }}>{error}</p>}

                  <button onClick={slipMode === "single" ? submitPick : submitAcca} disabled={loading || (slipMode === "acca" && betslip.length < 2)} style={{ width: "100%", padding: "12px", borderRadius: 10, border: "none", background: (slipMode === "acca" && betslip.length < 2) ? "#1e1e2a" : "linear-gradient(135deg, #f59e0b, #f97316)", color: (slipMode === "acca" && betslip.length < 2) ? "#4a4958" : "#000", fontSize: 14, fontWeight: 900, cursor: "pointer", letterSpacing: ".01em" }}>
                    {loading ? "Placing..." : slipMode === "single" ? "Place Prediction" : betslip.length < 2 ? "Add " + (2 - betslip.length) + " more pick" + (2 - betslip.length === 1 ? "" : "s") : "Place " + betslip.length + "-Fold Acca"}
                  </button>
                </div>
              )}
            </div>
          )}
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
    <div style={{ display: "flex", borderTop: "0.5px solid #2a2a32", background: "#141417", flexShrink: 0 }}>
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
  );
}

function FeedIcon()    { return <svg width="20" height="20" viewBox="0 0 20 20" fill="none"><path d="M3 5h14M3 10h14M3 15h8" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/></svg>; }
function BoardIcon()   { return <svg width="20" height="20" viewBox="0 0 20 20" fill="none"><path d="M4 15V9M8 15V5M12 15V8M16 15V11" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/></svg>; }
function PlusIcon()    { return <svg width="20" height="20" viewBox="0 0 20 20" fill="none"><circle cx="10" cy="10" r="7" stroke="currentColor" strokeWidth="1.5"/><path d="M10 7v6M7 10h6" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/></svg>; }
function LeagueIcon()  { return <svg width="20" height="20" viewBox="0 0 20 20" fill="none"><path d="M10 2l2 6h6l-5 3.5 2 6L10 14l-5 3.5 2-6L2 8h6z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round"/></svg>; }
function ProfileIcon() { return <svg width="20" height="20" viewBox="0 0 20 20" fill="none"><circle cx="10" cy="7" r="3" stroke="currentColor" strokeWidth="1.5"/><path d="M4 17c0-3.314 2.686-5 6-5s6 1.686 6 5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/></svg>; }

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
  root: { minHeight: "100vh", background: "#0d0d0f", display: "flex", alignItems: "center", justifyContent: "center", fontFamily: "'DM Sans', system-ui, sans-serif", padding: 20 },
  screen: { width: "100%", maxWidth: 400, height: 700, background: "#141417", border: "0.5px solid #2a2a32", borderRadius: 24, overflow: "hidden", position: "relative", display: "flex", flexDirection: "column" },
  header: { display: "flex", alignItems: "center", justifyContent: "space-between", padding: "18px 20px 14px", borderBottom: "0.5px solid #2a2a32", flexShrink: 0 },
  logo:    { fontSize: 18, fontWeight: 700, color: "#f0eff8", letterSpacing: "-.01em" },
  tagline: { fontSize: 12, color: "#4a4958" },
  back:    { background: "none", border: "none", color: "#6c63ff", fontSize: 13, cursor: "pointer", padding: 0 },
  body:    { padding: "20px 20px 32px", flex: 1, overflowY: "auto" },
  section: { padding: "12px 16px 0" },
  sectionLabel: { fontSize: 11, fontWeight: 600, color: "#4a4958", textTransform: "uppercase", letterSpacing: ".07em", marginBottom: 10 },
  card: { background: "#1a1a1f", border: "0.5px solid #2a2a32", borderRadius: 12, padding: "12px 14px", marginBottom: 8 },
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
  statCard: { background: "#1a1a1f", borderRadius: 10, border: "0.5px solid #2a2a32", padding: "10px 12px" },
  statLabel: { fontSize: 11, color: "#4a4958", margin: "0 0 4px", textTransform: "uppercase", letterSpacing: ".05em" },
  statVal:   { fontSize: 20, fontWeight: 700, margin: 0 },
  adminSectionTitle: { fontSize: 14, fontWeight: 600, color: "#f0eff8", margin: "0 0 6px" },
  adminBtn: { width: "100%", padding: "11px", borderRadius: 10, background: "#ef444420", border: "0.5px solid #ef444444", color: "#ef4444", fontSize: 13, fontWeight: 600, cursor: "pointer" },
  resolveBtn: { padding: "9px", borderRadius: 8, border: "0.5px solid", fontSize: 13, fontWeight: 600, cursor: "pointer" },
};
