import Testing
import Foundation
import DayblockCore

@Suite struct StreakTests {
    @Test func countsBackFromToday() {
        #expect(Streaks.current(solvedDays: [], today: 100) == 0)
        #expect(Streaks.current(solvedDays: [100], today: 100) == 1)
        #expect(Streaks.current(solvedDays: [98, 99, 100], today: 100) == 3)
    }

    @Test func staysAliveUntilTodayIsMissed() {
        // Yesterday solved, today not played yet: still a 2-day streak.
        #expect(Streaks.current(solvedDays: [98, 99], today: 100) == 2)
        // A whole day missed: gone.
        #expect(Streaks.current(solvedDays: [97, 98], today: 100) == 0)
    }

    @Test func gapsBreakTheStreak() {
        #expect(Streaks.current(solvedDays: [95, 96, 98, 99, 100], today: 100) == 3)
    }

    @Test func bestIsTheLongestRun() {
        #expect(Streaks.best(solvedDays: []) == 0)
        #expect(Streaks.best(solvedDays: [1, 2, 3, 10, 11, 20]) == 3)
        #expect(Streaks.best(solvedDays: [5]) == 1)
    }
}

@Suite struct ShareTextTests {
    @Test func perfectResult() {
        let text = ShareText.daily(number: 42, result: DailyResult(swipes: 7, par: 7, stars: 3))
        #expect(text == "Dayblock #42 · 7 swipes (best 7) ★★★\n🟩🟩🟩🟩🟩🟩🟩")
    }

    @Test func extrasAreYellow() {
        let text = ShareText.daily(number: 42, result: DailyResult(swipes: 8, par: 7, stars: 2))
        #expect(text == "Dayblock #42 · 8 swipes (best 7) ★★☆\n🟩🟩🟩🟩🟩🟩🟩🟨")
    }

    @Test func manyExtrasAreSummarised() {
        let text = ShareText.daily(number: 3, result: DailyResult(swipes: 30, par: 5, stars: 1), link: "https://example.com")
        #expect(text == "Dayblock #3 · 30 swipes (best 5) ★☆☆\n🟩🟩🟩🟩🟩🟨🟨🟨🟨🟨🟨🟨🟨 +17\nhttps://example.com")
    }

    @Test func survivesBadStarValues() {
        #expect(ShareText.daily(number: 1, result: DailyResult(swipes: 5, par: 5, stars: 9)).contains("★★★"))
        #expect(ShareText.daily(number: 1, result: DailyResult(swipes: 5, par: 5, stars: -2)).contains("☆☆☆"))
    }

    @Test func puzzleNumberNeverDropsBelowOne() {
        let early = PuzzleDate(year: 2020, month: 1, day: 1)
        #expect(early.puzzleNumber(launch: Dayblock.launchDate) == 1)
    }

    @Test func neverRevealsTheSolution() {
        let puzzle = Generator.daily(for: Dayblock.launchDate)
        let text = ShareText.daily(number: 1, result: DailyResult(swipes: puzzle.par, par: puzzle.par, stars: 3))
        for arrow in ["↑", "→", "↓", "←"] { #expect(!text.contains(arrow)) }
    }
}

@Suite struct SnapshotTests {
    let puzzle = Generator.daily(for: PuzzleDate(year: 2027, month: 1, day: 6))

    @Test func resumesExactlyWhereItLeftOff() throws {
        var session = GameSession(puzzle: puzzle)
        session.swipe(puzzle.solution[0])
        session.swipe(puzzle.solution[1])
        session.undo()
        let data = try JSONEncoder().encode(session.snapshot)
        let snapshot = try JSONDecoder().decode(GameSession.Snapshot.self, from: data)
        var resumed = try #require(GameSession(puzzle: puzzle, snapshot: snapshot))
        #expect(resumed.positions == session.positions)
        #expect(resumed.swipeCount == 2)
        #expect(resumed.canUndo)
        resumed.undo()
        #expect(resumed.positions == puzzle.startPositions)
    }

    @Test func rejectsASnapshotFromAnotherPuzzle() {
        let other = Generator.practice(seed: 7, difficulty: .expert)
        var session = GameSession(puzzle: other)
        session.swipe(other.solution[0])
        let easy = Generator.practice(seed: 7, difficulty: .easy)
        #expect(GameSession(puzzle: easy, snapshot: session.snapshot) == nil)
    }

    @Test func isoDatesRoundTrip() {
        let date = PuzzleDate(year: 2027, month: 3, day: 9)
        #expect(PuzzleDate(iso: date.iso) == date)
        #expect(PuzzleDate(iso: "nonsense") == nil)
        #expect(Dayblock.launchDate.puzzleNumber(launch: Dayblock.launchDate) == 1)
    }
}
