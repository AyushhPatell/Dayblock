import Testing
import Foundation
@testable import DayblockCore

@Suite struct LockRuleTests {
    @Test func slidingAcrossATargetDoesNotLock() {
        let board = Board(width: 4, height: 1)
        let puzzle = Puzzle(
            board: board, colorStarts: [0], targets: [1], greyStarts: [],
            difficulty: .easy, par: 1, solution: [.right], rules: .locking
        )
        var session = GameSession(puzzle: puzzle)
        let result = session.swipe(.right)
        #expect(result?.newlyLocked.isEmpty == true)
        #expect(session.positions == [3])
        // It passed the target, so the next tilt the other way still moves it.
        #expect(session.swipe(.left)?.moves.map(\.to) == [0])
    }

    @Test func restingOnATargetLocksAndStopsOtherBlocks() {
        // A is the right-hand block and homes on the first tilt. B is then stuck behind it.
        // Without the lock, that same second tilt would pull A off its target.
        let board = Board(width: 4, height: 1)
        let puzzle = Puzzle(
            board: board, colorStarts: [0, 2], targets: [3, 1], greyStarts: [],
            difficulty: .easy, par: 1, solution: [.left], rules: .locking
        )
        var session = GameSession(puzzle: puzzle)
        let parked = session.swipe(.left)
        #expect(parked?.newlyLocked == [1])
        #expect(session.positions == [0, 1])
        #expect(session.isSolved == false)
        let blocked = session.swipe(.right)
        #expect(blocked == nil)
        #expect(session.positions == [0, 1])
    }

    @Test func aGreyBlockNeverLocks() {
        let board = Board(width: 4, height: 1)
        let puzzle = Puzzle(
            board: board, colorStarts: [0], targets: [3], greyStarts: [2],
            difficulty: .easy, par: 2, solution: [], rules: .locking
        )
        var session = GameSession(puzzle: puzzle)
        let moved = session.swipe(.right)
        #expect(moved?.newlyLocked.isEmpty == true)
        #expect(session.positions == [2, 3])
        // The grey is sitting on the colour's target and can still leave.
        let left = session.swipe(.left)
        #expect(left?.moves.contains { $0.block == 1 } == true)
    }

    @Test func undoRefundsOnlyWhenTheRuleSaysSo() {
        let board = Board(width: 4, height: 1)
        func puzzle(_ rules: Rules) -> Puzzle {
            Puzzle(
            board: board, colorStarts: [0], targets: [2], greyStarts: [],
            difficulty: .easy, par: 1, solution: [.right], rules: rules
            )
        }
        var forgiving = GameSession(puzzle: puzzle(.locking))
        forgiving.swipe(.right)
        #expect(forgiving.swipeCount == 1)
        let refunded = forgiving.undo()
        #expect(refunded)
        #expect(forgiving.swipeCount == 0)
        #expect(forgiving.positions == [0])

        var classic = GameSession(puzzle: puzzle(.classic))
        classic.swipe(.right)
        let kept = classic.undo()
        #expect(kept)
        #expect(classic.swipeCount == 1)
        #expect(classic.positions == [0])
    }

    @Test func restartKeepsPenaltiesAndDropsTheRouteWhenUndoRefunds() {
        let board = Board(width: 4, height: 1)
        let puzzle = Puzzle(
            board: board, colorStarts: [0], targets: [2], greyStarts: [],
            difficulty: .easy, par: 1, solution: [.right], rules: .locking
        )
        var session = GameSession(puzzle: puzzle)
        session.swipe(.right)
        session.addPenaltySwipe()
        #expect(session.swipeCount == 2)
        session.restart()
        #expect(session.positions == [0])
        #expect(session.swipeCount == 1)
        #expect(session.canUndo == false)
    }

    @Test func oldSnapshotsAndPuzzlesDefaultToClassic() throws {
        let puzzle = Puzzle(
            board: Board(width: 3, height: 3), colorStarts: [0], targets: [8], greyStarts: [],
            difficulty: .easy, par: 2, solution: [.right, .down]
        )
        let body: [String: Any] = [
            "board": ["width": 3, "height": 3, "walls": []],
            "colorStarts": [0], "targets": [8], "greyStarts": [],
            "difficulty": "easy", "par": 2, "solution": [1, 2],
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let loaded = try JSONDecoder().decode(Puzzle.self, from: data)
        #expect(loaded.rules == .classic)
        #expect(loaded == puzzle)

        let snapshotBody: [String: Any] = ["positions": [0], "swipeCount": 4, "history": [[0]]]
        let snapshotData = try JSONSerialization.data(withJSONObject: snapshotBody)
        let snapshot = try JSONDecoder().decode(GameSession.Snapshot.self, from: snapshotData)
        var session = try #require(GameSession(puzzle: puzzle, snapshot: snapshot))
        #expect(session.swipeCount == 4)
        session.undo()
        #expect(session.swipeCount == 4)
    }

    @Test func solverMatchesABruteForceSearchOnASmallLockingBoard() {
        let board = Board(width: 4, height: 4, walls: [Wall(x: 1, y: 1, side: .bottom)])
        let starts = [0, 5]
        let targets = [12, 3]
        let solver = Solver.solve(board: board, positions: starts, targets: targets, locks: true)
        #expect(solver?.count == bruteLockPar(board: board, positions: starts, targets: targets))
        var positions = starts
        for move in solver?.moves ?? [] {
            positions = Board.lockedSlide(board, positions, move, targets: targets)
        }
        #expect(positions[0] == targets[0])
        #expect(positions[1] == targets[1])
    }

    @Test func classicDailiesStayPinned() {
        let first = Generator.daily(for: PuzzleDate(year: 2026, month: 11, day: 14))
        let friday = Generator.daily(for: PuzzleDate(year: 2026, month: 11, day: 20))
        #expect(first.rules == .classic)
        #expect(friday.rules == .classic)
        #expect(first.par == LockPins.november14.par)
        #expect(first.colorStarts == LockPins.november14.starts)
        #expect(first.targets == LockPins.november14.targets)
        #expect(first.greyStarts == LockPins.november14.greys)
        #expect(first.solution.map(\.rawValue) == LockPins.november14.moves)
        #expect(friday.par == LockPins.november20.par)
        #expect(friday.colorStarts == LockPins.november20.starts)
        #expect(friday.targets == LockPins.november20.targets)
        #expect(friday.greyStarts == LockPins.november20.greys)
        #expect(friday.solution.map(\.rawValue) == LockPins.november20.moves)
    }

    @Test func lockRulePracticeIsDeterministicAndSolvable() throws {
        for difficulty in Difficulty.allCases {
            for seed in 0..<12 as Range<UInt64> {
                let puzzle = Generator.practice(seed: seed, difficulty: difficulty, rules: .locking)
                let again = Generator.practice(seed: seed, difficulty: difficulty, rules: .locking)
                #expect(puzzle == again)
                #expect(puzzle.rules == .locking)
                let solved = try #require(Solver.solve(puzzle))
                #expect(solved.count == puzzle.par)
                var session = GameSession(puzzle: puzzle)
                for move in puzzle.solution { session.swipe(move) }
                #expect(session.isSolved)
            }
        }
    }
}

private enum LockPins {
    struct Pin {
        let par: Int
        let starts: [Int]
        let targets: [Int]
        let greys: [Int]
        let moves: [UInt8]
    }
    static let november14 = Pin(
        par: 8, starts: [1, 2, 16], targets: [30, 0, 12], greys: [4],
        moves: [3, 2, 1, 0, 3, 2, 3, 0]
    )
    static let november20 = Pin(
        par: 9, starts: [22, 33, 1], targets: [6, 31, 29], greys: [17, 7],
        moves: [2, 3, 0, 3, 0, 1, 0, 1, 2]
    )
}

private func bruteLockPar(board: Board, positions: [Int], targets: [Int]) -> Int? {
    if positions[0] == targets[0], positions[1] == targets[1] { return 0 }
    var queue = [positions]
    var seen: Set<[Int]> = [positions]
    var index = 0
    var depth = 0
    var levelEnd = 1
    while index < queue.count && depth < 12 {
        if index == levelEnd {
            depth += 1
            levelEnd = queue.count
        }
        let current = queue[index]
        index += 1
        for direction in Direction.allCases {
            let next = Board.lockedSlide(board, current, direction, targets: targets)
            if next == current || !seen.insert(next).inserted { continue }
            if next[0] == targets[0], next[1] == targets[1] { return depth + 1 }
            queue.append(next)
        }
    }
    return nil
}

private extension Board {
    static func lockedSlide(_ board: Board, _ positions: [Int], _ direction: Direction, targets: [Int]) -> [Int] {
        var fixed = [Bool](repeating: false, count: positions.count)
        for index in 0..<min(2, positions.count) where positions[index] == targets[index] {
            fixed[index] = true
        }
        return board.slide(positions, direction, fixed: fixed)
    }
}
