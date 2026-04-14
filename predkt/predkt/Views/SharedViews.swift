import SwiftUI

// MARK: - Team DNA System
// Every team is assigned a geometric pattern based on their traditional kit.
// All shapes are generic geometric forms — legally safe, not trademarkable.
// No club badges, crests, or official imagery used.

// MARK: - Pattern Types

enum TeamPattern {
    case vertical(color1: Color, color2: Color, stripes: Int)   // e.g. Newcastle, Juventus, AC Milan
    case hoops(color1: Color, color2: Color, stripes: Int)      // e.g. Celtic, QPR, Brentford
    case solid(color: Color, ringColor: Color)                  // e.g. Chelsea, Real Madrid, Man City
    case sash(color1: Color, color2: Color)                     // e.g. Crystal Palace, River Plate
    case halves(colorLeft: Color, colorRight: Color)            // e.g. Blackburn, Galatasaray
    case quarters(color1: Color, color2: Color)                 // e.g. Wolves, Watford
}

// MARK: - Team DNA Library
// Maps team names to their pattern archetype.
// Add any team by matching their traditional home kit.

struct TeamDNA {

    // Predefined colours
    private static let red       = Color(red:0.85, green:0.10, blue:0.10)
    private static let darkRed   = Color(red:0.65, green:0.05, blue:0.05)
    private static let blue      = Color(red:0.10, green:0.25, blue:0.80)
    private static let lightBlue = Color(red:0.40, green:0.65, blue:0.95)
    private static let skyBlue   = Color(red:0.30, green:0.70, blue:0.95)
    private static let navy      = Color(red:0.05, green:0.10, blue:0.40)
    private static let white     = Color.white
    private static let black     = Color(red:0.08, green:0.08, blue:0.08)
    private static let yellow    = Color(red:0.98, green:0.82, blue:0.10)
    private static let gold      = Color(red:0.92, green:0.68, blue:0.10)
    private static let orange    = Color(red:0.98, green:0.45, blue:0.05)
    private static let green     = Color(red:0.10, green:0.55, blue:0.20)
    private static let claret    = Color(red:0.55, green:0.05, blue:0.20)
    private static let purple    = Color(red:0.45, green:0.10, blue:0.70)
    private static let maroon    = Color(red:0.50, green:0.05, blue:0.10)
    private static let amber     = Color(red:0.98, green:0.60, blue:0.05)
    private static let lime      = Color(red:0.60, green:0.85, blue:0.10)
    private static let gray      = Color(red:0.55, green:0.55, blue:0.60)
    private static let pink      = Color(red:0.95, green:0.40, blue:0.65)

    // MARK: - Pattern lookup

    static func pattern(for teamName: String) -> TeamPattern {
        switch teamName.lowercased() {

        // ── PREMIER LEAGUE ──────────────────────────────────────────────────

        case "arsenal":
            return .solid(color: red, ringColor: white)
        case "aston villa":
            return .halves(colorLeft: claret, colorRight: skyBlue)
        case "bournemouth":
            return .vertical(color1: red, color2: black, stripes: 4)
        case "brentford":
            return .hoops(color1: red, color2: white, stripes: 4)
        case "brighton", "brighton & hove albion":
            return .vertical(color1: skyBlue, color2: white, stripes: 4)
        case "burnley":
            return .halves(colorLeft: claret, colorRight: skyBlue)
        case "chelsea":
            return .solid(color: blue, ringColor: gold)
        case "crystal palace":
            return .sash(color1: red, color2: blue)
        case "everton":
            return .solid(color: blue, ringColor: white)
        case "fulham":
            return .vertical(color1: white, color2: black, stripes: 3)
        case "ipswich", "ipswich town":
            return .solid(color: blue, ringColor: white)
        case "leicester", "leicester city":
            return .solid(color: blue, ringColor: gold)
        case "liverpool":
            return .solid(color: red, ringColor: Color(red:0.92,green:0.65,blue:0.10))
        case "luton", "luton town":
            return .hoops(color1: orange, color2: white, stripes: 4)
        case "manchester city", "man city":
            return .hoops(color1: skyBlue, color2: white, stripes: 3)
        case "manchester united", "man united", "man utd":
            return .solid(color: red, ringColor: yellow)
        case "newcastle", "newcastle united":
            return .vertical(color1: black, color2: white, stripes: 3)
        case "nottingham forest":
            return .solid(color: red, ringColor: white)
        case "sheffield united":
            return .vertical(color1: red, color2: white, stripes: 4)
        case "southampton":
            return .vertical(color1: red, color2: white, stripes: 3)
        case "tottenham", "tottenham hotspur", "spurs":
            return .solid(color: white, ringColor: navy)
        case "west ham", "west ham united":
            return .halves(colorLeft: claret, colorRight: skyBlue)
        case "wolves", "wolverhampton", "wolverhampton wanderers":
            return .solid(color: gold, ringColor: black)

        // ── CHAMPIONSHIP ────────────────────────────────────────────────────

        case "leeds", "leeds united":
            return .solid(color: white, ringColor: yellow)
        case "sunderland":
            return .vertical(color1: red, color2: white, stripes: 3)
        case "middlesbrough":
            return .solid(color: red, ringColor: white)
        case "sheffield wednesday":
            return .hoops(color1: blue, color2: white, stripes: 4)
        case "coventry", "coventry city":
            return .solid(color: skyBlue, ringColor: white)
        case "hull", "hull city":
            return .halves(colorLeft: amber, colorRight: black)
        case "blackburn", "blackburn rovers":
            return .halves(colorLeft: blue, colorRight: white)
        case "watford":
            return .quarters(color1: yellow, color2: black)
        case "norwich", "norwich city":
            return .halves(colorLeft: yellow, colorRight: green)
        case "qpr", "queens park rangers":
            return .hoops(color1: blue, color2: white, stripes: 3)
        case "stoke", "stoke city":
            return .vertical(color1: red, color2: white, stripes: 3)
        case "millwall":
            return .solid(color: navy, ringColor: white)
        case "swansea", "swansea city":
            return .solid(color: white, ringColor: black)
        case "cardiff", "cardiff city":
            return .solid(color: blue, ringColor: Color(red:0.75,green:0.60,blue:0.05))

        // ── CHAMPIONS LEAGUE / EUROPE ────────────────────────────────────────

        case "real madrid":
            return .solid(color: white, ringColor: gold)
        case "barcelona", "fc barcelona":
            return .vertical(color1: Color(red:0.60,green:0.05,blue:0.15), color2: Color(red:0.05,green:0.20,blue:0.65), stripes: 4)
        case "atletico madrid":
            return .vertical(color1: red, color2: white, stripes: 4)
        case "sevilla", "sevilla fc":
            return .solid(color: white, ringColor: red)
        case "villarreal":
            return .solid(color: yellow, ringColor: Color(red:0.05,green:0.30,blue:0.15))
        case "ac milan":
            return .vertical(color1: red, color2: black, stripes: 4)
        case "inter", "inter milan", "internazionale":
            return .vertical(color1: navy, color2: black, stripes: 4)
        case "juventus":
            return .vertical(color1: black, color2: white, stripes: 3)
        case "napoli":
            return .solid(color: Color(red:0.05,green:0.55,blue:0.85), ringColor: white)
        case "as roma", "roma":
            return .solid(color: Color(red:0.75,green:0.15,blue:0.05), ringColor: gold)
        case "lazio":
            return .solid(color: skyBlue, ringColor: white)
        case "fiorentina":
            return .solid(color: purple, ringColor: white)
        case "atalanta":
            return .vertical(color1: black, color2: Color(red:0.05,green:0.40,blue:0.75), stripes: 3)
        case "torino":
            return .solid(color: maroon, ringColor: white)
        case "bologna", "bologna fc":
            return .halves(colorLeft: red, colorRight: navy)
        case "udinese":
            return .vertical(color1: black, color2: white, stripes: 3)
        case "borussia dortmund", "dortmund":
            return .solid(color: yellow, ringColor: black)
        case "bayern munich", "bayern münchen", "fc bayern":
            return .quarters(color1: red, color2: white)
        case "rb leipzig":
            return .solid(color: red, ringColor: white)
        case "bayer leverkusen", "leverkusen":
            return .solid(color: red, ringColor: black)
        case "borussia mönchengladbach", "monchengladbach":
            return .vertical(color1: white, color2: green, stripes: 3)
        case "schalke", "schalke 04":
            return .solid(color: Color(red:0.05,green:0.30,blue:0.70), ringColor: white)
        case "psg", "paris saint-germain", "paris saint germain":
            return .sash(color1: navy, color2: red)
        case "lyon", "olympique lyonnais":
            return .halves(colorLeft: white, colorRight: Color(red:0.60,green:0.05,blue:0.10))
        case "marseille", "olympique de marseille":
            return .solid(color: white, ringColor: skyBlue)
        case "monaco", "as monaco":
            return .halves(colorLeft: red, colorRight: white)
        case "celtic":
            return .hoops(color1: green, color2: white, stripes: 5)
        case "rangers":
            return .solid(color: Color(red:0.05,green:0.15,blue:0.65), ringColor: white)
        case "ajax":
            return .vertical(color1: white, color2: red, stripes: 3)
        case "psv", "psv eindhoven":
            return .vertical(color1: red, color2: white, stripes: 3)
        case "feyenoord":
            return .halves(colorLeft: red, colorRight: white)
        case "porto", "fc porto":
            return .halves(colorLeft: Color(red:0.55,green:0.00,blue:0.55), colorRight: white)
        case "benfica", "sl benfica":
            return .solid(color: red, ringColor: Color(red:0.90,green:0.75,blue:0.10))
        case "sporting cp", "sporting":
            return .hoops(color1: green, color2: white, stripes: 4)
        case "galatasaray":
            return .halves(colorLeft: red, colorRight: yellow)
        case "fenerbahce":
            return .halves(colorLeft: yellow, colorRight: navy)
        case "besiktas":
            return .vertical(color1: black, color2: white, stripes: 3)

        default:
            return fallbackPattern(for: teamName)
        }
    }

    // Deterministic fallback for unknown teams — uses name hash for variety
    private static func fallbackPattern(for name: String) -> TeamPattern {
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        let colors: [(Color, Color)] = [
            (blue, white), (red, white), (green, white), (navy, gold),
            (black, white), (purple, white), (skyBlue, white), (claret, skyBlue),
        ]
        let pair  = colors[abs(hash) % colors.count]
        let style = abs(hash / colors.count) % 5

        switch style {
        case 0: return .solid(color: pair.0, ringColor: pair.1)
        case 1: return .vertical(color1: pair.0, color2: pair.1, stripes: 3)
        case 2: return .hoops(color1: pair.0, color2: pair.1, stripes: 3)
        case 3: return .halves(colorLeft: pair.0, colorRight: pair.1)
        default:return .sash(color1: pair.0, color2: pair.1)
        }
    }
}

// MARK: - TeamBadgeView (public API — same signature as before)

struct TeamBadgeView: View {
    let url: String?
    let teamName: String?

    init(url: String?, teamName: String? = nil) {
        self.url      = url
        self.teamName = teamName
    }

    var body: some View {
        GeometricBadge(teamName: teamName ?? "")
    }
}

// MARK: - GeometricBadge
// Renders the correct pattern for a team in a square with rounded corners

struct GeometricBadge: View {
    let teamName: String

    var body: some View {
        let pattern = TeamDNA.pattern(for: teamName)
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                patternView(pattern: pattern, size: size)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
        }
    }

    @ViewBuilder
    private func patternView(pattern: TeamPattern, size: CGFloat) -> some View {
        switch pattern {

        case .vertical(let c1, let c2, let n):
            VerticalStripesShape(stripes: n)
                .fill(stripeFill(c1, c2, n, vertical: true, size: size))
                .overlay(RoundedRectangle(cornerRadius: size * 0.18).stroke(c1.opacity(0.6), lineWidth: size * 0.04))

        case .hoops(let c1, let c2, let n):
            VerticalStripesShape(stripes: n)
                .fill(stripeFill(c1, c2, n, vertical: false, size: size))
                .overlay(RoundedRectangle(cornerRadius: size * 0.18).stroke(c1.opacity(0.6), lineWidth: size * 0.04))

        case .solid(let c, let ring):
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.18).fill(c)
                RoundedRectangle(cornerRadius: size * 0.18)
                    .stroke(ring.opacity(0.85), lineWidth: size * 0.08)
                    .blur(radius: size * 0.03)
                RoundedRectangle(cornerRadius: size * 0.18)
                    .stroke(ring, lineWidth: size * 0.05)
            }

        case .sash(let c1, let c2):
            ZStack {
                c2  // background
                SashShape()
                    .fill(c1)
            }
            .overlay(RoundedRectangle(cornerRadius: size * 0.18).stroke(c1.opacity(0.5), lineWidth: size * 0.04))

        case .halves(let cL, let cR):
            ZStack {
                HStack(spacing: 0) {
                    cL.frame(maxWidth: .infinity)
                    cR.frame(maxWidth: .infinity)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: size * 0.18).stroke(Color.white.opacity(0.15), lineWidth: size * 0.04))

        case .quarters(let c1, let c2):
            ZStack {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        c1.frame(maxWidth: .infinity)
                        c2.frame(maxWidth: .infinity)
                    }.frame(maxHeight: .infinity)
                    HStack(spacing: 0) {
                        c2.frame(maxWidth: .infinity)
                        c1.frame(maxWidth: .infinity)
                    }.frame(maxHeight: .infinity)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: size * 0.18).stroke(Color.white.opacity(0.15), lineWidth: size * 0.04))
        }
    }

    // Build a LinearGradient with hard stops for crisp stripes
    private func stripeFill(_ c1: Color, _ c2: Color, _ n: Int, vertical: Bool, size: CGFloat) -> LinearGradient {
        var stops: [Gradient.Stop] = []
        let step = 1.0 / Double(n)
        for i in 0..<n {
            let start = Double(i) * step
            let end   = start + step
            let color = i % 2 == 0 ? c1 : c2
            stops.append(.init(color: color, location: start))
            stops.append(.init(color: color, location: end))
        }
        return LinearGradient(
            stops: stops,
            startPoint: vertical ? .leading : .top,
            endPoint:   vertical ? .trailing : .bottom
        )
    }
}

// MARK: - Custom Shapes

// Used for both vertical and horizontal stripes (direction set by gradient)
struct VerticalStripesShape: Shape {
    let stripes: Int
    func path(in rect: CGRect) -> Path {
        Path(rect)
    }
}

// Diagonal sash from top-left to bottom-right (~30% width)
struct SashShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let sash = w * 0.38 // sash width
        p.move(to:    CGPoint(x: w * 0.25,        y: 0))
        p.addLine(to: CGPoint(x: w * 0.25 + sash, y: 0))
        p.addLine(to: CGPoint(x: w * 0.75,        y: h))
        p.addLine(to: CGPoint(x: w * 0.75 - sash, y: h))
        p.closeSubpath()
        return p
    }
}

// MARK: - MatchCardView (Feed)

struct MatchCardView: View {
    let match: Match

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                TeamBadgeView(url: match.homeLogo, teamName: match.home)
                    .frame(width: 20, height: 20)
                Text(match.home)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if match.isLive || match.isFinished {
                Text(match.score)
                    .font(.system(size: 13, weight: .black)).foregroundStyle(.white)
            } else {
                Text(match.kickoffTime)
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.predktLime)
            }

            HStack(spacing: 6) {
                Text(match.away)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white).lineLimit(1).multilineTextAlignment(.trailing)
                TeamBadgeView(url: match.awayLogo, teamName: match.away)
                    .frame(width: 20, height: 20)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.predktCard).cornerRadius(10)
    }
}
