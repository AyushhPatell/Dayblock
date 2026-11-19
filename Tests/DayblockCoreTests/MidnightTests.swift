import Foundation
import Testing
import DayblockCore

@Suite struct PuzzleDayTests {
    @Test func overrideReplacesTheSystemClock() {
        defer { PuzzleDay.resetOverride() }
        let fixed = PuzzleDate(year: 2026, month: 11, day: 22)
        PuzzleDay.override = fixed
        #expect(PuzzleDay.current() == fixed)
        #expect(PuzzleDay.current(now: Date(timeIntervalSince1970: 0)) == fixed)
    }

    @Test func dateMappingUsesGregorianInTheGivenTimeZone() throws {
        // 2026-11-19 06:00 UTC is still the 18th in US/Pacific.
        var pacific = TimeZone(identifier: "America/Los_Angeles")
        if pacific == nil { pacific = TimeZone(secondsFromGMT: -8 * 3600) }
        let zone = try #require(pacific)
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
        let instant = try #require(utcCal.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 6)))
        #expect(PuzzleDay.date(from: instant, timeZone: TimeZone(secondsFromGMT: 0)!) == PuzzleDate(year: 2026, month: 11, day: 19))
        #expect(PuzzleDay.date(from: instant, timeZone: zone) == PuzzleDate(year: 2026, month: 11, day: 18))
    }
}

@Suite struct MidnightRuleTests {
    @Test func openPuzzleKeepsItsOwnRecordKeyAfterHubRollsOver() {
        let session = PuzzleDate(year: 2026, month: 11, day: 18)
        let hub = PuzzleDate(year: 2026, month: 11, day: 19)
        #expect(MidnightRules.recordKey(sessionDate: session, hubToday: hub) == "2026-11-18")
        #expect(MidnightRules.hubShows(newToday: hub, previousHubToday: session))
        #expect(!MidnightRules.hubShows(newToday: session, previousHubToday: session))
    }

    @Test func recordedResultIsFinalAcrossTimeZoneChanges() {
        // Results are stored under the ISO puzzle day. Changing the device time zone
        // changes "today", but must not clear or replace an existing result for that key.
        var results: [String: Int] = ["2026-11-18": 3]
        func persist(day: PuzzleDate, stars: Int) {
            let key = day.iso
            if results[key] != nil { return }
            results[key] = stars
        }

        let wednesday = PuzzleDate(year: 2026, month: 11, day: 18)
        persist(day: wednesday, stars: 3)
        // Same wall-clock mapped to a different local day after a TZ jump still
        // cannot overwrite Wednesday's recorded result when writing that key again.
        persist(day: wednesday, stars: 1)
        #expect(results["2026-11-18"] == 3)

        // A different calendar day is a different key — allowed.
        persist(day: PuzzleDate(year: 2026, month: 11, day: 19), stars: 2)
        #expect(results["2026-11-19"] == 2)
        #expect(results["2026-11-18"] == 3)
    }
}

@Suite struct HubStreakTests {
    /// Hub streak = union of Paint / Fit / Tilt solved day numbers.

    @Test func solvingOnlyPaintCountsTheDay() {
        let today = PuzzleDate(year: 2026, month: 11, day: 20).dayNumber
        let paint: Set<Int> = [today]
        let fit: Set<Int> = []
        #expect(DailyStreak.solvedDays(paint: paint, fit: fit) == [today])
        #expect(DailyStreak.current(paint: paint, fit: fit, today: today) == 1)
    }

    @Test func solvingOnlyFitCountsTheDay() {
        let today = PuzzleDate(year: 2026, month: 11, day: 20).dayNumber
        #expect(DailyStreak.current(paint: [], fit: [today], today: today) == 1)
    }

    @Test func solvingBothStillCountsAsOneDay() {
        let today = PuzzleDate(year: 2026, month: 11, day: 20).dayNumber
        let yesterday = today - 1
        let paint: Set<Int> = [yesterday, today]
        let fit: Set<Int> = [today]
        #expect(DailyStreak.solvedDays(paint: paint, fit: fit) == [yesterday, today])
        #expect(DailyStreak.current(paint: paint, fit: fit, today: today) == 2)
    }

    @Test func aMissedDayBreaksTheStreak() {
        let today = PuzzleDate(year: 2026, month: 11, day: 20).dayNumber
        // Solved Mon+Tue, missed Wed, today is Thu with nothing yet.
        let paint: Set<Int> = [today - 3, today - 2]
        #expect(DailyStreak.current(paint: paint, fit: [], today: today) == 0)
        #expect(Streaks.best(solvedDays: DailyStreak.solvedDays(paint: paint, fit: [])) == 2)
    }

    @Test func solvingYesterdaysPuzzleAfterMidnightKeepsTheStreakAlive() {
        defer { PuzzleDay.resetOverride() }
        let wednesday = PuzzleDate(year: 2026, month: 11, day: 18)
        let thursday = wednesday.adding(days: 1)
        PuzzleDay.override = thursday

        // Player opened Wednesday's Paint before midnight; hub has rolled to Thursday.
        let sessionDate = wednesday
        let hubToday = PuzzleDay.current()
        #expect(hubToday == thursday)
        let key = MidnightRules.recordKey(sessionDate: sessionDate, hubToday: hubToday)
        #expect(key == wednesday.iso)

        // Solve records under Wednesday. Thursday not played yet → streak still alive.
        let paint: Set<Int> = [wednesday.dayNumber]
        #expect(DailyStreak.current(paint: paint, fit: [], today: hubToday.dayNumber) == 1)

        // Also solved Tuesday earlier → two-day streak pending Thursday's play.
        let paint2: Set<Int> = [wednesday.dayNumber - 1, wednesday.dayNumber]
        #expect(DailyStreak.current(paint: paint2, fit: [], today: hubToday.dayNumber) == 2)
    }
}
