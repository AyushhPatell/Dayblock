import Testing
import Foundation
import DayblockCore

@Suite struct SlidePropertyTests {
    @Test func randomSlidesKeepTheRules() {
        var random = SeededRandom(seed: 0x51_1DE)
        for _ in 0..<40 {
            let board = randomBoard(&random)
            let count = random.int(in: 1...min(4, board.cellCount - 1))
            let positions = randomCells(board, count: count, random: &random)
            for direction in Direction.allCases {
                let once = board.slide(positions, direction)
                let twice = board.slide(once, direction)
                #expect(twice == once)
                assertLegalSlide(board, from: positions, direction: direction, result: once)

                if positions.count > 1 {
                    var shuffled = positions
                    var expected = once
                    shuffled.swapAt(0, positions.count - 1)
                    expected.swapAt(0, positions.count - 1)
                    #expect(board.slide(shuffled, direction) == expected)
                }
            }
        }
    }

    @Test func reversedBlockOrderReversesTheResult() {
        var random = SeededRandom(seed: 99)
        for _ in 0..<20 {
            let board = randomBoard(&random)
            let positions = randomCells(board, count: 3, random: &random)
            for direction in Direction.allCases {
                let forward = board.slide(positions, direction)
                let backward = board.slide(Array(positions.reversed()), direction)
                #expect(Array(backward.reversed()) == forward)
            }
        }
    }
}

@Suite struct SolverPropertyTests {
    @Test func storedSolutionsReplayToSolved() throws {
        let seeds: [UInt64] = [1, 2, 3, 4, 8, 13]
        for seed in seeds {
            for difficulty in [Difficulty.easy, .medium] {
                let puzzle = Generator.practice(seed: seed, difficulty: difficulty)
                let solved = try #require(Solver.solve(puzzle))
                #expect(solved.count == puzzle.par)
                var positions = puzzle.startPositions
                for move in solved.moves {
                    positions = puzzle.board.slide(positions, move)
                }
                #expect(puzzle.isSolved(positions))
            }
        }
    }

    @Test func parMatchesAnIndependentSearchOnSmallBoards() {
        var random = SeededRandom(seed: 0xB207)
        for _ in 0..<24 {
            let size = random.int(in: 3...4)
            var walls: [Wall] = []
            if random.int(below: 2) == 0 {
                walls.append(Wall(x: random.int(below: size - 1), y: random.int(below: size), side: .right))
            }
            let board = Board(width: size, height: size, walls: walls)
            var positions = randomCells(board, count: random.int(in: 1...2), random: &random)
            for _ in 0..<random.int(in: 1...4) {
                positions = board.slide(positions, Direction.allCases[random.int(below: 4)])
            }
            let targets = [positions[0]]
            let start = randomCells(board, count: positions.count, random: &random)
            let brute = brutePar(board: board, positions: start, targets: targets, maxDepth: 8)
            let solver = Solver.solve(board: board, positions: start, targets: targets)
            if let brute {
                #expect(solver?.count == brute)
            } else if let solver, solver.count <= 8 {
                #expect(Bool(false), "brute force missed a solution of length \(solver.count)")
            }
        }
    }

    @Test func reportsUnsolvableAndStopsAtTheNodeCap() {
        let row = Board(width: 5, height: 1)
        // A lone stopper on the end can park the coloured block on cell 3, never on cell 2.
        #expect(Solver.solve(board: row, positions: [0, 4], targets: [2]) == nil)
        #expect(Solver.solve(board: row, positions: [0, 4], targets: [3])?.count == 1)

        let board = Board(width: 4, height: 4)
        let full = Solver.solve(board: board, positions: [0], targets: [15])
        #expect(full?.count == 2)
        // The cap is hit before the second tilt, so a real solution must not be returned.
        #expect(Solver.solve(board: board, positions: [0], targets: [15], maxNodes: 1) == nil)
    }
}

@Suite struct SessionPropertyTests {
    @Test func randomSessionsStayConsistent() throws {
        var random = SeededRandom(seed: 0x5E55)
        let puzzles = [
            Generator.practice(seed: 3, difficulty: .easy),
            Generator.practice(seed: 4, difficulty: .medium),
            Generator.daily(for: PuzzleDate(year: 2026, month: 11, day: 16)),
        ]
        for puzzle in puzzles {
            var session = GameSession(puzzle: puzzle)
            var previousSwipes = 0
            for _ in 0..<60 {
                switch random.int(below: 10) {
                case 0: session.undo()
                case 1: session.restart()
                case 2: session.addPenaltySwipe()
                default:
                    session.swipe(Direction.allCases[random.int(below: 4)])
                }
                #expect(session.swipeCount >= previousSwipes)
                previousSwipes = session.swipeCount
                let cells = 0..<puzzle.board.cellCount
                #expect(session.positions.count == puzzle.startPositions.count)
                #expect(Set(session.positions).count == session.positions.count)
                #expect(session.positions.allSatisfy(cells.contains))

                if session.isSolved {
                    let swipes = session.swipeCount
                    let positions = session.positions
                    #expect(session.undo() == false)
                    session.addPenaltySwipe()
                    session.restart()
                    session.swipe(.left)
                    #expect(session.swipeCount == swipes)
                    #expect(session.positions == positions)
                }

                let resumed = try #require(GameSession(puzzle: puzzle, snapshot: session.snapshot))
                #expect(resumed.positions == session.positions)
                #expect(resumed.swipeCount == session.swipeCount)
                #expect(resumed.canUndo == session.canUndo)
                let data = try JSONEncoder().encode(session.snapshot)
                let decoded = try JSONDecoder().decode(GameSession.Snapshot.self, from: data)
                let roundTrip = try #require(GameSession(puzzle: puzzle, snapshot: decoded))
                #expect(roundTrip.snapshot == resumed.snapshot)
            }
        }
    }

    @Test func rejectsSnapshotsThatDoNotFitThePuzzle() throws {
        let puzzle = Puzzle(
            board: Board(width: 3, height: 3),
            colorStarts: [0, 1], targets: [2, 5], greyStarts: [],
            difficulty: .easy, par: 2, solution: [.right, .down]
        )
        #expect(try session(puzzle, positions: [0], swipeCount: 0, history: []) == nil)
        #expect(try session(puzzle, positions: [0, 0], swipeCount: 0, history: []) == nil)
        #expect(try session(puzzle, positions: [0, 99], swipeCount: 0, history: []) == nil)
        #expect(try session(puzzle, positions: [0, 2], swipeCount: -1, history: []) == nil)
        #expect(try session(puzzle, positions: [0, 2], swipeCount: 1, history: [[0, 0]]) == nil)
        #expect(try session(puzzle, positions: [0, 2], swipeCount: 1, history: [[0]]) == nil)
        let accepted = try #require(try session(puzzle, positions: [0, 2], swipeCount: 1, history: [[0, 1]]))
        #expect(accepted.swipeCount == 1)
        #expect(accepted.canUndo)
    }
}

@Suite struct DatePropertyTests {
    @Test func rejectsDatesThatAreNotRealDays() {
        let rejected = [
            "2026-02-31", "2026-13-01", "2026-00-10", "2026-11-00", "2026-04-31",
            "2025-02-29", "1900-02-29", "2026-11-14-1", "2026-11-14 ", " 2026-11-14",
            "2026--11-14", "2026-11", "", "2026-11-14 ", "nonsense", "2026-2-31",
        ]
        for text in rejected {
            #expect(PuzzleDate(iso: text) == nil, "\(text) should be rejected")
        }
        #expect(PuzzleDate(iso: "2024-02-29") != nil)
        #expect(PuzzleDate(iso: "2000-02-29") != nil)
        #expect(PuzzleDate(iso: "2026-11-14") == PuzzleDate(year: 2026, month: 11, day: 14))
    }

    @Test func leapYearsCenturyYearsAndYearBoundaries() {
        let feb28 = PuzzleDate(year: 1900, month: 2, day: 28)
        let march = PuzzleDate(year: 1900, month: 3, day: 1)
        #expect(march.dayNumber - feb28.dayNumber == 1)
        #expect(PuzzleDate(year: 2000, month: 2, day: 28).adding(days: 1) == PuzzleDate(year: 2000, month: 2, day: 29))
        #expect(PuzzleDate(year: 2000, month: 2, day: 29).adding(days: 1) == PuzzleDate(year: 2000, month: 3, day: 1))
        #expect(PuzzleDate(year: 2024, month: 2, day: 28).adding(days: 1) == PuzzleDate(year: 2024, month: 2, day: 29))
        #expect(PuzzleDate(year: 2025, month: 2, day: 28).adding(days: 1) == PuzzleDate(year: 2025, month: 3, day: 1))
        #expect(PuzzleDate(year: 1999, month: 12, day: 31).adding(days: 1) == PuzzleDate(year: 2000, month: 1, day: 1))
        #expect(PuzzleDate(year: 2026, month: 12, day: 31).adding(days: 1) == PuzzleDate(year: 2027, month: 1, day: 1))
        #expect(PuzzleDate(year: 1970, month: 1, day: 1).dayNumber == 0)
        #expect(PuzzleDate(year: 1969, month: 12, day: 31).dayNumber == -1)
        #expect(PuzzleDate(dayNumber: 0) == PuzzleDate(year: 1970, month: 1, day: 1))
    }

    @Test func addingDaysMatchesTheSystemCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let epoch = PuzzleDate(year: 1970, month: 1, day: 1)
        for offset in stride(from: -400, to: 20_000, by: 17) {
            let shifted = epoch.adding(days: offset)
            let parts = calendar.dateComponents(
                [.year, .month, .day], from: Date(timeIntervalSince1970: Double(offset) * 86_400)
            )
            #expect(shifted == PuzzleDate(year: parts.year!, month: parts.month!, day: parts.day!))
            #expect(shifted.dayNumber == offset)
        }
    }
}

@Suite struct GeneratorPropertyTests {
    @Test func theSameDailyComesOutOfConcurrentTasks() async {
        let date = PuzzleDate(year: 2026, month: 11, day: 16)
        let expected = Generator.daily(for: date)
        let repeats = await withTaskGroup(of: Puzzle.self) { group in
            for _ in 0..<8 {
                group.addTask { Generator.daily(for: date) }
            }
            var matches = 0
            for await puzzle in group where puzzle == expected {
                matches += 1
            }
            return matches
        }
        #expect(repeats == 8)
        #expect(Generator.daily(for: date) == expected)
    }
}

@Suite struct AuditSanityTests {
    @Test func countsTheTwoRoutesAcrossAnOpenBoard() {
        let board = Board(width: 4, height: 4)
        let puzzle = Puzzle(
            board: board, colorStarts: [0], targets: [15], greyStarts: [],
            difficulty: .easy, par: 2, solution: [.right, .down]
        )
        let profile = PuzzleAudit.profile(puzzle, luckTrials: 6, luckSeed: 1)
        #expect(profile.directionCount == 2)
        #expect(profile.oneSlideHome == false)
        #expect(profile.shortestSolutions == 2)
        #expect(profile.optimalFirstMoves == 2)
        #expect(profile.greysAreDecorative == false)
        #expect(profile.wallsAreDecorative == false)
        #expect(profile.luckTrials == 6)
        #expect(profile.luckSolves >= 0)
    }

    @Test func aGreyStopperIsNotDecorative() {
        let puzzle = Puzzle(
            board: Board(width: 5, height: 1),
            colorStarts: [0], targets: [3], greyStarts: [4],
            difficulty: .easy, par: 1, solution: [.right]
        )
        let profile = PuzzleAudit.profile(puzzle, luckTrials: 4, luckSeed: 2)
        #expect(profile.hasGreys)
        #expect(profile.greysAreDecorative == false)
        #expect(profile.shortestSolutions >= 1)
    }
}

private func randomBoard(_ random: inout SeededRandom) -> Board {
    let size = random.int(in: 2...6)
    var walls: [Wall] = []
    let wanted = random.int(below: size)
    var tries = 0
    while walls.count < wanted && tries < 40 {
        tries += 1
        let side: Wall.Side = random.int(below: 2) == 0 ? .right : .bottom
        let x = random.int(below: side == .right ? size - 1 : size)
        let y = random.int(below: side == .bottom ? size - 1 : size)
        let wall = Wall(x: x, y: y, side: side)
        if !walls.contains(wall) { walls.append(wall) }
    }
    return Board(width: size, height: size, walls: walls)
}

private func randomCells(_ board: Board, count: Int, random: inout SeededRandom) -> [Int] {
    var cells = Array(0..<board.cellCount)
    for index in 0..<count {
        cells.swapAt(index, index + random.int(below: cells.count - index))
    }
    return Array(cells.prefix(count))
}

private func assertLegalSlide(_ board: Board, from positions: [Int], direction: Direction, result: [Int]) {
    #expect(result.count == positions.count)
    #expect(Set(result).count == result.count)
    let step: Int
    switch direction {
    case .right: step = 1
    case .left: step = -1
    case .down: step = board.width
    case .up: step = -board.width
    }
    for index in positions.indices {
        let start = positions[index]
        let end = result[index]
        #expect((0..<board.cellCount).contains(end))
        switch direction {
        case .left, .right:
            #expect(board.y(of: start) == board.y(of: end))
            #expect(direction == .right ? board.x(of: end) >= board.x(of: start) : board.x(of: end) <= board.x(of: start))
        case .up, .down:
            #expect(board.x(of: start) == board.x(of: end))
            #expect(direction == .down ? board.y(of: end) >= board.y(of: start) : board.y(of: end) <= board.y(of: start))
        }
        if start != end {
            var cell = start
            var guardCount = 0
            while cell != end && guardCount < board.cellCount {
                #expect(!board.isBlocked(cell, direction))
                cell += step
                guardCount += 1
            }
            #expect(cell == end)
        }
        if !board.isBlocked(end, direction) {
            #expect(result.contains(end + step))
        }
    }
}

/// Breadth-first search that does not use `Solver` or `Search`.
private func brutePar(board: Board, positions: [Int], targets: [Int], maxDepth: Int) -> Int? {
    func solved(_ positions: [Int]) -> Bool {
        positions[0] == targets[0]
    }
    if solved(positions) { return 0 }
    var queue = [positions]
    var seen: Set<[Int]> = [positions]
    var index = 0
    var depth = 0
    var levelEnd = 1
    while index < queue.count && depth < maxDepth {
        if index == levelEnd {
            depth += 1
            levelEnd = queue.count
        }
        let current = queue[index]
        index += 1
        for direction in Direction.allCases {
            let next = board.slide(current, direction)
            if next == current || !seen.insert(next).inserted { continue }
            if solved(next) { return depth + 1 }
            queue.append(next)
        }
    }
    return nil
}

private func session(
    _ puzzle: Puzzle, positions: [Int], swipeCount: Int, history: [[Int]]
) throws -> GameSession? {
    let body: [String: Any] = ["positions": positions, "swipeCount": swipeCount, "history": history]
    let data = try JSONSerialization.data(withJSONObject: body)
    let snapshot = try JSONDecoder().decode(GameSession.Snapshot.self, from: data)
    return GameSession(puzzle: puzzle, snapshot: snapshot)
}
