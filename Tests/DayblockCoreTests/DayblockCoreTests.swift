import Testing
import Foundation
import DayblockCore

@Suite struct SlideTests {
    let open = Board(width: 5, height: 5)

    @Test func blockSlidesToTheEdge() {
        #expect(open.slide([open.cell(x: 1, y: 2)], .right) == [open.cell(x: 4, y: 2)])
        #expect(open.slide([open.cell(x: 1, y: 2)], .left) == [open.cell(x: 0, y: 2)])
        #expect(open.slide([open.cell(x: 1, y: 2)], .up) == [open.cell(x: 1, y: 0)])
        #expect(open.slide([open.cell(x: 1, y: 2)], .down) == [open.cell(x: 1, y: 4)])
    }

    @Test func blockStopsAtAWall() {
        let board = Board(width: 5, height: 5, walls: [Wall(x: 2, y: 0, side: .right), Wall(x: 0, y: 2, side: .bottom)])
        #expect(board.slide([board.cell(x: 0, y: 0)], .right) == [board.cell(x: 2, y: 0)])
        #expect(board.slide([board.cell(x: 4, y: 0)], .left) == [board.cell(x: 3, y: 0)])
        #expect(board.slide([board.cell(x: 0, y: 0)], .down) == [board.cell(x: 0, y: 2)])
        #expect(board.slide([board.cell(x: 0, y: 4)], .up) == [board.cell(x: 0, y: 3)])
    }

    @Test func blocksStackAgainstEachOther() {
        let row = [open.cell(x: 0, y: 1), open.cell(x: 2, y: 1), open.cell(x: 3, y: 1)]
        #expect(open.slide(row, .right) == [open.cell(x: 2, y: 1), open.cell(x: 3, y: 1), open.cell(x: 4, y: 1)])
        #expect(open.slide(row, .left) == [open.cell(x: 0, y: 1), open.cell(x: 1, y: 1), open.cell(x: 2, y: 1)])
    }

    @Test func orderOfBlocksInTheListDoesNotMatter() {
        let a = [open.cell(x: 3, y: 1), open.cell(x: 0, y: 1)]
        #expect(open.slide(a, .right) == [open.cell(x: 4, y: 1), open.cell(x: 3, y: 1)])
    }

    @Test func blocksInDifferentRowsMoveIndependently() {
        let positions = [open.cell(x: 1, y: 0), open.cell(x: 3, y: 4)]
        #expect(open.slide(positions, .down) == [open.cell(x: 1, y: 4), open.cell(x: 3, y: 4)])
    }
}

@Suite struct SolverTests {
    @Test func findsTheShortestSolution() throws {
        let board = Board(width: 5, height: 5)
        // Corner to opposite corner needs exactly two tilts.
        let solution = try #require(Solver.solve(board: board, positions: [0], targets: [24]))
        #expect(solution.count == 2)
        var positions = [0]
        for move in solution.moves { positions = board.slide(positions, move) }
        #expect(positions == [24])
    }

    @Test func alreadySolvedNeedsNoMoves() {
        let board = Board(width: 5, height: 5)
        #expect(Solver.solve(board: board, positions: [7], targets: [7])?.count == 0)
    }

    @Test func reportsWhenThereIsNoSolution() {
        // On an empty board a lone block can only ever rest on the border.
        let board = Board(width: 5, height: 5)
        #expect(Solver.solve(board: board, positions: [0], targets: [12]) == nil)
    }

    @Test func greyBlockCanBeUsedAsAStopper() throws {
        // Block 0 must stop mid-row; only the grey block makes that possible.
        let board = Board(width: 5, height: 1)
        let solution = try #require(Solver.solve(board: board, positions: [0, 4], targets: [3]))
        #expect(solution.moves == [.right])
    }
}

@Suite struct DateTests {
    @Test func weekdaysAreCorrect() {
        #expect(PuzzleDate(year: 1970, month: 1, day: 1).weekday == .thursday)
        #expect(PuzzleDate(year: 2026, month: 11, day: 14).weekday == .saturday)
        #expect(PuzzleDate(year: 2024, month: 2, day: 29).weekday == .thursday)
        #expect(PuzzleDate(year: 2027, month: 1, day: 1).weekday == .friday)
    }

    @Test func matchesTheSystemCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        for offset in stride(from: 0, to: 4000, by: 37) {
            let date = Date(timeIntervalSince1970: Double(offset + 20_000) * 86_400)
            let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
            let puzzleDate = PuzzleDate(year: parts.year!, month: parts.month!, day: parts.day!)
            #expect(puzzleDate.dayNumber == offset + 20_000)
            // Calendar: Sunday = 1. Ours: Monday = 0.
            #expect(puzzleDate.weekday.rawValue == (parts.weekday! + 5) % 7)
        }
    }

    @Test func formatsAndNumbers() {
        let launch = PuzzleDate(year: 2027, month: 1, day: 4)
        #expect(launch.iso == "2027-01-04")
        #expect(launch.puzzleNumber(launch: launch) == 1)
        #expect(PuzzleDate(year: 2027, month: 2, day: 1).puzzleNumber(launch: launch) == 29)
    }
}

@Suite struct GeneratorTests {
    static func expectedPar(for weekday: PuzzleDate.Weekday) -> ClosedRange<Int> {
        switch weekday {
        case .monday: return 3...4
        case .tuesday: return 4...5
        case .wednesday, .thursday: return 6...7
        case .friday, .saturday: return 8...10
        case .sunday: return 10...13
        }
    }

    static func dates(_ count: Int) -> [PuzzleDate] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return (0..<count).map { offset in
            let date = Date(timeIntervalSince1970: Double(20_800 + offset) * 86_400)
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return PuzzleDate(year: parts.year!, month: parts.month!, day: parts.day!)
        }
    }

    @Test func sameDateAlwaysGivesTheSamePuzzle() {
        for date in Self.dates(14) {
            #expect(Generator.daily(for: date) == Generator.daily(for: date))
        }
    }

    @Test func differentDatesGiveDifferentPuzzles() {
        let puzzles = Self.dates(60).map { Generator.daily(for: $0) }
        #expect(Set(puzzles).count == puzzles.count)
    }

    @Test func everyDailyPuzzleIsValid() throws {
        for date in Self.dates(120) {
            let puzzle = Generator.daily(for: date)
            #expect(puzzle.difficulty == Generator.difficulty(for: date.weekday))
            let expectedPar = Self.expectedPar(for: date.weekday)

            // Blocks and targets sit on distinct cells, and nobody starts at home.
            let start = puzzle.startPositions
            #expect(Set(start).count == start.count)
            #expect(Set(puzzle.targets).count == puzzle.targets.count)
            for colour in 0..<puzzle.colorCount {
                #expect(puzzle.colorStarts[colour] != puzzle.targets[colour])
                // No target starts hidden under a block.
                #expect(!start.contains(puzzle.targets[colour]))
            }

            // The stored solution really solves it, in exactly `par` swipes.
            #expect(puzzle.solution.count == puzzle.par)
            var positions = start
            for move in puzzle.solution { positions = puzzle.board.slide(positions, move) }
            #expect(puzzle.isSolved(positions))

            // An independent solve agrees that nothing shorter exists.
            let solved = try #require(Solver.solve(puzzle))
            #expect(solved.count == puzzle.par)

            #expect(expectedPar.contains(puzzle.par), "\(date.iso) \(date.weekday) par \(puzzle.par)")
        }
    }

    @Test func practicePuzzlesAreValidAtEveryDifficulty() throws {
        for difficulty in Difficulty.allCases {
            for seed in 0..<40 as Range<UInt64> {
                let puzzle = Generator.practice(seed: seed, difficulty: difficulty)
                let solved = try #require(Solver.solve(puzzle))
                #expect(solved.count == puzzle.par)
            }
        }
    }

    @Test func puzzlesSurviveSavingAndLoading() throws {
        let puzzle = Generator.daily(for: PuzzleDate(year: 2027, month: 1, day: 10))
        let data = try JSONEncoder().encode(puzzle)
        let loaded = try JSONDecoder().decode(Puzzle.self, from: data)
        #expect(loaded == puzzle)
        #expect(loaded.board.slide(loaded.startPositions, .left) == puzzle.board.slide(puzzle.startPositions, .left))
    }
}

@Suite struct GameSessionTests {
    let puzzle = Generator.daily(for: PuzzleDate(year: 2027, month: 1, day: 6))

    @Test func playingTheSolutionWinsWithThreeStars() {
        var session = GameSession(puzzle: puzzle)
        #expect(session.stars == nil)
        for move in puzzle.solution {
            let result = session.swipe(move)
            #expect(result != nil)
        }
        #expect(session.isSolved)
        #expect(session.swipeCount == puzzle.par)
        #expect(session.stars == 3)
        // Nothing more can happen once solved.
        let extraSwipe = session.swipe(.up)
        let extraUndo = session.undo()
        #expect(extraSwipe == nil)
        #expect(extraUndo == false)
    }

    @Test func swipeThatMovesNothingIsNotCounted() {
        let lone = Puzzle(board: Board(width: 3, height: 3), colorStarts: [0], targets: [8], greyStarts: [],
                          difficulty: .easy, par: 2, solution: [.right, .down])
        var session = GameSession(puzzle: lone)
        let left = session.swipe(.left)
        let up = session.swipe(.up)
        #expect(left == nil)
        #expect(up == nil)
        #expect(session.swipeCount == 0)
        let result = session.swipe(.right)
        #expect(result?.moves == [GameSession.BlockMove(block: 0, from: 0, to: 2)])
        #expect(result?.solved == false)
        #expect(session.swipeCount == 1)
    }

    @Test func undoAndRestartDoNotRefundSwipes() {
        var session = GameSession(puzzle: puzzle)
        let first = puzzle.solution[0]
        session.swipe(first)
        let afterFirst = session.positions
        let undone = session.undo()
        #expect(undone)
        #expect(session.positions == puzzle.startPositions)
        #expect(session.swipeCount == 1)
        let undoneAgain = session.undo()
        #expect(undoneAgain == false)
        session.swipe(first)
        #expect(session.positions == afterFirst)
        session.restart()
        #expect(session.positions == puzzle.startPositions)
        #expect(session.swipeCount == 2)
    }

    @Test func hintFollowsAShortestRoute() {
        var session = GameSession(puzzle: puzzle)
        var used = 0
        while !session.isSolved, used < 50 {
            guard let hint = session.hint() else { break }
            session.swipe(hint)
            used += 1
        }
        #expect(session.isSolved)
        #expect(used == puzzle.par)
    }

    @Test func penaltySwipeCountsButMovesNothing() {
        var session = GameSession(puzzle: puzzle)
        session.addPenaltySwipe()
        #expect(session.swipeCount == 1)
        #expect(session.positions == puzzle.startPositions)
        #expect(session.canUndo == false)
        for move in puzzle.solution { session.swipe(move) }
        #expect(session.swipeCount == puzzle.par + 1)
        #expect(session.stars == 2)
        session.addPenaltySwipe()
        #expect(session.swipeCount == puzzle.par + 1)
    }

    @Test func starsDropWithExtraSwipes() {
        #expect(puzzle.stars(forSwipes: puzzle.par) == 3)
        #expect(puzzle.stars(forSwipes: puzzle.par + 1) == 2)
        #expect(puzzle.stars(forSwipes: puzzle.par + 2) == 2)
        #expect(puzzle.stars(forSwipes: puzzle.par + 3) == 1)
    }
}
