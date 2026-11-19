public enum Dayblock {
    /// The date of daily puzzle #1. Set this to the real launch day before release.
    public static let launchDate = PuzzleDate(year: 2026, month: 11, day: 14)
}

extension PuzzleDate {
    /// Parses "2026-11-14". Rejects impossible days, extra pieces, and whitespace.
    public init?(iso: String) {
        let pieces = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3,
              let year = Int(pieces[0]),
              let month = Int(pieces[1]),
              let day = Int(pieces[2]),
              Self.isValid(year: year, month: month, day: day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }
}

/// How a finished daily puzzle went.
public struct DailyResult: Codable, Equatable, Sendable {
    public let swipes: Int
    public let par: Int
    public let stars: Int

    public init(swipes: Int, par: Int, stars: Int) {
        self.swipes = swipes
        self.par = par
        self.stars = stars
    }
}

public enum Streaks {
    /// Days in a row solved, counted back from today. A streak is still alive
    /// if yesterday was solved and today has not been played yet.
    public static func current(solvedDays: Set<Int>, today: Int) -> Int {
        var day = solvedDays.contains(today) ? today : today - 1
        var count = 0
        while solvedDays.contains(day) {
            count += 1
            day -= 1
        }
        return count
    }

    /// The longest run of consecutive solved days ever.
    public static func best(solvedDays: Set<Int>) -> Int {
        var best = 0
        for day in solvedDays where !solvedDays.contains(day - 1) {
            var length = 1
            while solvedDays.contains(day + length) { length += 1 }
            best = max(best, length)
        }
        return best
    }
}

public enum ShareText {
    /// The spoiler-free result people post, for example:
    ///
    ///     Dayblock #42 · 8 swipes (best 7) ★★☆
    ///     🟩🟩🟩🟩🟩🟩🟩🟨
    ///
    /// One square per swipe: green up to the best possible, yellow for extras.
    public static func daily(number: Int, result: DailyResult, link: String? = nil) -> String {
        let earned = min(3, max(0, result.stars))
        let stars = String(repeating: "★", count: earned) + String(repeating: "☆", count: 3 - earned)
        let unit = result.swipes == 1 ? "swipe" : "swipes"
        var lines = ["Dayblock #\(number) · \(result.swipes) \(unit) (best \(result.par)) \(stars)"]
        let extras = max(0, result.swipes - result.par)
        let shownExtras = min(extras, 8)
        var squares = String(repeating: "🟩", count: min(result.swipes, result.par))
        squares += String(repeating: "🟨", count: shownExtras)
        if extras > shownExtras { squares += " +\(extras - shownExtras)" }
        lines.append(squares)
        if let link { lines.append(link) }
        return lines.joined(separator: "\n")
    }
}
