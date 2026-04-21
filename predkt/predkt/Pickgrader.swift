import Foundation

/// Pure grading logic — no network calls, no side effects.
/// Returns "correct", "wrong", or nil (market can't be resolved from final score alone).
struct PickGrader {

    static func grade(
        market: String,
        home: String,
        away: String,
        homeGoals h: Int,
        awayGoals a: Int
    ) -> String? {

        let total = h + a
        func won(_ condition: Bool) -> String { condition ? "correct" : "wrong" }

        // ── FULL-TIME RESULT ─────────────────────────────────────────────────
        if market == "\(home) Win" { return won(h > a) }
        if market == "Draw"        { return won(h == a) }  // also covers Winning Margin draw
        if market == "\(away) Win" { return won(a > h) }

        // ── DOUBLE CHANCE ────────────────────────────────────────────────────
        if market == "\(home) or Draw"  { return won(h >= a) }
        if market == "Either team wins" { return won(h != a) }
        if market == "\(away) or Draw"  { return won(a >= h) }

        // ── DRAW NO BET (label is just the bare team name) ───────────────────
        if market == home { return h == a ? nil : won(h > a) }  // push on draw → leave pending
        if market == away { return h == a ? nil : won(a > h) }

        // ── BOTH TEAMS TO SCORE ──────────────────────────────────────────────
        if market == "Yes — both teams score"       { return won(h > 0 && a > 0) }
        if market == "No — at least one team blank" { return won(h == 0 || a == 0) }

        // ── OVER / UNDER GOALS ───────────────────────────────────────────────
        if market == "Over 0.5 goals"  { return won(total >= 1) }
        if market == "Under 0.5 goals" { return won(total == 0) }
        if market == "Over 1.5 goals"  { return won(total >= 2) }
        if market == "Under 1.5 goals" { return won(total <= 1) }
        if market == "Over 2.5 goals"  { return won(total >= 3) }
        if market == "Under 2.5 goals" { return won(total <= 2) }
        if market == "Over 3.5 goals"  { return won(total >= 4) }
        if market == "Under 3.5 goals" { return won(total <= 3) }
        if market == "Over 4.5 goals"  { return won(total >= 5) }
        if market == "Under 4.5 goals" { return won(total <= 4) }

        // ── GOALS ODD / EVEN ─────────────────────────────────────────────────
        if market == "Odd total goals"  { return won(total % 2 == 1) }
        if market == "Even total goals" { return won(total % 2 == 0) }

        // ── CORRECT SCORE FT — format "1-0", "2-1", "0-0" ───────────────────
        // Only matches pure "digit(s)-digit(s)" — not "HT: 1-0" or "2H: 1-0"
        let csParts = market.components(separatedBy: "-")
        if csParts.count == 2 {
            let lhs = csParts[0].trimmingCharacters(in: .whitespaces)
            let rhs = csParts[1].trimmingCharacters(in: .whitespaces)
            if !lhs.isEmpty, !rhs.isEmpty,
               lhs.allSatisfy({ $0.isNumber }),
               rhs.allSatisfy({ $0.isNumber }),
               let ph = Int(lhs), let pa = Int(rhs) {
                return won(h == ph && a == pa)
            }
        }

        // ── WIN TO NIL ───────────────────────────────────────────────────────
        if market == "\(home) win & clean sheet" { return won(h > a && a == 0) }
        if market == "\(away) win & clean sheet" { return won(a > h && h == 0) }

        // ── BTTS & WINNER ────────────────────────────────────────────────────
        if market == "Both score & \(home) win" { return won(h > 0 && a > 0 && h > a) }
        if market == "Both score & draw"         { return won(h > 0 && a > 0 && h == a) }
        if market == "Both score & \(away) win" { return won(h > 0 && a > 0 && a > h) }

        // ── EXACT GOALS ──────────────────────────────────────────────────────
        if market == "No goals (0)" { return won(total == 0) }
        if market == "Exactly 1"    { return won(total == 1) }
        if market == "Exactly 2"    { return won(total == 2) }
        if market == "Exactly 3"    { return won(total == 3) }
        if market == "Exactly 4"    { return won(total == 4) }
        if market == "5 or more"    { return won(total >= 5) }

        // ── HOME TEAM GOALS ──────────────────────────────────────────────────
        if market == "\(home) score 1+" { return won(h >= 1) }
        if market == "\(home) score 0"  { return won(h == 0) }
        if market == "\(home) score 2+" { return won(h >= 2) }
        if market == "\(home) under 2"  { return won(h < 2) }
        if market == "\(home) score 3+" { return won(h >= 3) }

        // ── AWAY TEAM GOALS ──────────────────────────────────────────────────
        if market == "\(away) score 1+" { return won(a >= 1) }
        if market == "\(away) score 0"  { return won(a == 0) }
        if market == "\(away) score 2+" { return won(a >= 2) }
        if market == "\(away) under 2"  { return won(a < 2) }
        if market == "\(away) score 3+" { return won(a >= 3) }

        // ── ASIAN HANDICAP ───────────────────────────────────────────────────
        if market == "\(home) -0.5" { return won(h > a) }
        if market == "\(away) -0.5" { return won(a > h) }
        if market == "\(home) -1.5" { return won(h >= a + 2) }
        if market == "\(away) -1.5" { return won(a >= h + 2) }

        // ── WINNING MARGIN ───────────────────────────────────────────────────
        if market == "\(home) win by 1"  { return won(h - a == 1) }
        if market == "\(home) win by 2"  { return won(h - a == 2) }
        if market == "\(home) win by 3+" { return won(h - a >= 3) }
        if market == "\(away) win by 1"  { return won(a - h == 1) }
        if market == "\(away) win by 2"  { return won(a - h == 2) }
        if market == "\(away) win by 3+" { return won(a - h >= 3) }

        // ── CLEAN SHEET ──────────────────────────────────────────────────────
        if market == "\(home) keep a clean sheet" { return won(a == 0) }
        if market == "\(away) keep a clean sheet" { return won(h == 0) }

        // ── UNRESOLVABLE ─────────────────────────────────────────────────────
        // HT/FT combos, first-half markets, second-half markets, correct score HT/2H,
        // BTTS first/second half, corners, cards, shots, player props.
        // These need data the Match model doesn't store — leave as pending.
        return nil
    }
}
