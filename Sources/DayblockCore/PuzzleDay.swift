import Foundation

/// The puzzle calendar day. Always Gregorian, in a chosen time zone.
///
/// Production reads the system clock through `current()`. Tests and debug
/// launch args inject a fixed day via `override` so they never call `Date()`
/// for "today" themselves.
public enum PuzzleDay: Sendable {
    private static let lock = NSLock()
    private static nonisolated(unsafe) var _override: PuzzleDate?

    /// When set, `current()` returns this and ignores the system clock.
    public static var override: PuzzleDate? {
        get { lock.withLock { _override } }
        set { lock.withLock { _override = newValue } }
    }

    public static func resetOverride() { override = nil }

    /// Gregorian calendar pinned to `timeZone` (never the device's preferred calendar).
    public static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// Maps a wall-clock instant to a puzzle day in `timeZone`.
    public static func date(from date: Date, timeZone: TimeZone = .current) -> PuzzleDate {
        let parts = calendar(timeZone: timeZone).dateComponents([.year, .month, .day], from: date)
        return PuzzleDate(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Today's puzzle day. Uses `override` when injected; otherwise the system clock.
    public static func current(now: Date = Date(), timeZone: TimeZone = .current) -> PuzzleDate {
        if let override { return override }
        return date(from: now, timeZone: timeZone)
    }
}

/// How the hub merges solved dailies from each game into one streak.
public enum DailyStreak {
    /// A calendar day counts when any daily that day was solved.
    public static func solvedDays(paint: Set<Int>, fit: Set<Int>, tilt: Set<Int> = []) -> Set<Int> {
        paint.union(fit).union(tilt)
    }

    public static func current(paint: Set<Int>, fit: Set<Int>, tilt: Set<Int> = [], today: Int) -> Int {
        Streaks.current(solvedDays: solvedDays(paint: paint, fit: fit, tilt: tilt), today: today)
    }
}

/// Pure rules for midnight rollover: hub cards move on; an open daily keeps its date.
public enum MidnightRules {
    /// The ISO key a solve records under — always the session's own day, never hub "today".
    public static func recordKey(sessionDate: PuzzleDate, hubToday: PuzzleDate) -> String {
        _ = hubToday
        return sessionDate.iso
    }

    /// Whether hub cards should show `newToday` after a clock change while a daily is open.
    public static func hubShows(newToday: PuzzleDate, previousHubToday: PuzzleDate) -> Bool {
        newToday != previousHubToday
    }
}
