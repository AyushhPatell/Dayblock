import Foundation
import Testing
@testable import DayblockCore

private func paintBoard(_ rows: [String]) -> (PaintBoard, Int) {
    // "#" solid, "o" pad, "S" start, anything else floor.
    let width = rows[0].count
    var open: [Bool] = [], pads: [Bool] = []
    var start = 0
    for (y, row) in rows.enumerated() {
        for (x, character) in row.enumerated() {
            open.append(character != "#")
            pads.append(character == "o")
            if character == "S" { start = y * width + x }
        }
    }
    return (PaintBoard(width: width, height: rows.count, open: open, pads: pads), start)
}

private func days(_ count: Int, from start: PuzzleDate = PuzzleDate(year: 2026, month: 11, day: 16)) -> [PuzzleDate] {
    (0..<count).map { start.adding(days: $0) }
}

@Suite struct PaintRuleTests {
    @Test func blockSlidesToTheWallAndPaintsTheWay() {
        let (board, start) = paintBoard(["S...#", "#####"])
        let move = board.move(from: start, .right)
        #expect(move.to == 3)
        #expect(move.painted == 0b1110)
        #expect(board.pathCells(from: start, .right) == [1, 2, 3])
        #expect(board.move(from: start, .left).to == start)
    }

    @Test func padStopsTheBlockOnEntry() {
        let (board, start) = paintBoard(["S.o.."])
        #expect(board.move(from: start, .right).to == 2)
        // Leaving a pad is fine; it only stops a block coming in.
        #expect(board.move(from: 2, .right).to == 4)
    }

    @Test func undoGivesTheSwipeBackAndRestartClearsTheRoute() {
        // S stops against the solid cell, then a staircase down to the corner.
        let (board, start) = paintBoard(["S.#", "#..", "##."])
        let puzzle = PaintPuzzle(board: board, start: start, difficulty: .easy, par: 4, solution: [.right, .down, .right, .down])
        var session = PaintSession(puzzle: puzzle)
        let first = session.swipe(.right)
        #expect(first?.newlyPainted == [1])
        let second = session.swipe(.left)
        #expect(second != nil)
        #expect(session.swipeCount == 2)
        let undone = session.undo()
        #expect(undone)
        #expect(session.swipeCount == 1)
        #expect(session.position == 1)
        session.restart()
        #expect(session.swipeCount == 0)
        #expect(session.cellsLeft == 4)
    }

    @Test func solvedSessionStopsChangingAndScores() throws {
        let (board, start) = paintBoard(["S.#", "#..", "##."])
        let puzzle = PaintPuzzle(board: board, start: start, difficulty: .easy, par: 4, solution: [])
        var session = PaintSession(puzzle: puzzle)
        let route = try #require(PaintSolver.solve(puzzle))
        #expect(route == [.right, .down, .right, .down])
        for move in route { session.swipe(move) }
        #expect(session.isSolved)
        let late = session.swipe(.up)
        let lateUndo = session.undo()
        #expect(late == nil)
        #expect(lateUndo == false)
        #expect(session.stars == puzzle.stars(forSwipes: route.count))
    }

    @Test func hintCapsStarsAtTwo() throws {
        let puzzle = PaintGenerator.level(5)
        var session = PaintSession(puzzle: puzzle)
        while !session.isSolved {
            let hint = session.takeHint()
            let next = try #require(hint)
            session.swipe(next)
        }
        #expect(session.swipeCount == puzzle.par)
        #expect(session.stars == 2)
    }

    @Test func snapshotRoundTripsAndRejectsNonsense() throws {
        let puzzle = PaintGenerator.daily(for: PuzzleDate(year: 2026, month: 11, day: 20))
        var session = PaintSession(puzzle: puzzle)
        session.swipe(puzzle.solution[0])
        session.swipe(puzzle.solution[1])
        let data = try JSONEncoder().encode(session.snapshot)
        let loaded = try JSONDecoder().decode(PaintSession.Snapshot.self, from: data)
        let resumed = try #require(PaintSession(puzzle: puzzle, snapshot: loaded))
        #expect(resumed.position == session.position)
        #expect(resumed.painted == session.painted)
        // A route that teleports is rejected.
        let bogus = PaintSession.Snapshot(route: [loaded.route[0], .init(position: loaded.route[0].position, painted: 0)], hintsUsed: 0)
        #expect(PaintSession(puzzle: puzzle, snapshot: bogus) == nil)
    }
}

@Suite struct PaintSolverTests {
    /// Independent check: try every swipe sequence up to `depth` long.
    private func bruteForce(_ board: PaintBoard, start: Int, depth: Int) -> Int? {
        var frontier: [(Int, UInt64)] = [(start, 1 << UInt64(start))]
        for length in 0...depth {
            if frontier.contains(where: { $0.1 == board.floorMask }) { return length }
            var next: [(Int, UInt64)] = []
            for (position, painted) in frontier {
                for direction in Direction.allCases {
                    let move = board.move(from: position, direction)
                    if move.to != position { next.append((move.to, painted | move.painted)) }
                }
            }
            frontier = next
        }
        return nil
    }

    @Test func parMatchesBruteForceOnSmallPuzzles() {
        for level in 1...12 {
            let puzzle = PaintGenerator.level(level)
            #expect(bruteForce(puzzle.board, start: puzzle.start, depth: puzzle.par) == puzzle.par, "level \(level)")
        }
    }

    @Test func storedSolutionReplays() {
        for date in days(21) {
            let puzzle = PaintGenerator.daily(for: date)
            var session = PaintSession(puzzle: puzzle)
            for move in puzzle.solution { session.swipe(move) }
            #expect(session.isSolved, "\(date.iso)")
            #expect(puzzle.solution.count == puzzle.par)
        }
    }

    @Test func detectsBoardsWhereYouCanGetStuck() {
        // The check is deliberately strict: a start in the middle of a corridor
        // can never be rested on again, so the board is not accepted, even though
        // this particular one could still be finished.
        let (middle, start) = paintBoard([".S."])
        #expect(!PaintSolver.isAlwaysFinishable(middle, start: start))
        // A straight corridor can always go back and forth.
        let (fine, fineStart) = paintBoard(["S.."])
        #expect(PaintSolver.isAlwaysFinishable(fine, start: fineStart))
        // A floor cell no route ever crosses makes it unfinishable too.
        let (unreachable, s) = paintBoard(["S..", "#.#", "#.."])
        #expect(!PaintSolver.isAlwaysFinishable(unreachable, start: s))
    }
}

@Suite struct PaintGeneratorTests {
    @Test func dailiesAreDeterministicDistinctAndFair() {
        var seen = Set<PaintPuzzle>()
        for date in days(56) {
            let puzzle = PaintGenerator.daily(for: date)
            #expect(puzzle == PaintGenerator.daily(for: date))
            seen.insert(puzzle)
            #expect(PaintSolver.isAlwaysFinishable(puzzle.board, start: puzzle.start), "\(date.iso) can trap the player")
            #expect(PaintGenerator.config(for: date.weekday).par.contains(puzzle.par), "\(date.iso) par \(puzzle.par)")
            #expect(puzzle.board.width * puzzle.board.height <= 49)
        }
        #expect(seen.count == 56)
    }

    @Test func levelsRampUp() {
        let early = (1...5).map { PaintGenerator.level($0).par }
        let late = (100...104).map { PaintGenerator.level($0).par }
        #expect(early.max()! < late.min()!)
    }
}

@Suite struct FitRuleTests {
    @Test func rotationTurnsClockwiseAndComesBack() {
        let el = FitPiece(cells: [FitCell(x: 0, y: 0), FitCell(x: 0, y: 1), FitCell(x: 1, y: 1)])
        let turned = el.rotated(1)
        #expect(turned.cells == [FitCell(x: 0, y: 0), FitCell(x: 1, y: 0), FitCell(x: 0, y: 1)])
        #expect(el.rotated(4) == el)
        #expect(FitPiece(cells: [FitCell(x: 0, y: 0), FitCell(x: 1, y: 0), FitCell(x: 0, y: 1), FitCell(x: 1, y: 1)]).distinctRotations == [0])
    }

    @Test func rotatingAPlacedPieceKeepsItOrReturnsItToTheTray() {
        // Wednesday onwards: pieces turn. Place one answer piece, then turn it.
        let puzzle = FitGenerator.daily(for: PuzzleDate(year: 2026, month: 11, day: 18))
        #expect(puzzle.rotates)
        var session = FitSession(puzzle: puzzle)
        let piece = 0
        let answer = puzzle.solution[piece]
        while session.rotations[piece] != answer.rotation { session.rotate(piece) }
        #expect(session.place(piece, x: answer.x, y: answer.y) == .fits)
        #expect(session.placements[piece] != nil)

        session.rotate(piece)
        if let placement = session.placements[piece] {
            #expect(placement.rotation == (answer.rotation + 1) % 4)
            #expect(placement.x == answer.x)
            #expect(placement.y == answer.y)
        } else {
            #expect(session.rotations[piece] == (answer.rotation + 1) % 4)
        }
    }

    @Test func placementChecksOutlineOverlapAndClues() {
        let puzzle = FitGenerator.daily(for: PuzzleDate(year: 2026, month: 11, day: 19))
        var session = FitSession(puzzle: puzzle)
        #expect(session.check(0, x: -1, y: 0) == .outside)
        // Put every piece where the answer has it, turning tray pieces first.
        for piece in puzzle.pieces.indices {
            while session.rotations[piece] != puzzle.solution[piece].rotation { session.rotate(piece) }
            let result = session.place(piece, x: puzzle.solution[piece].x, y: puzzle.solution[piece].y)
            #expect(result == .fits)
        }
        #expect(session.isSolved)
        #expect(session.stars == 3)
    }

    @Test func aClueRejectsTheWrongSize() throws {
        let puzzle = try #require((0..<60).lazy.map { FitGenerator.level($0 + 1) }.first { !$0.clues.isEmpty && Set($0.pieces.map(\.size)).count > 1 })
        let clue = puzzle.clues[0]
        let wrong = try #require(puzzle.pieces.indices.first { puzzle.pieces[$0].size != clue.size })
        let session = FitSession(puzzle: puzzle)
        var sawClue = false
        for rotation in puzzle.allowedRotations(wrong) {
            for cell in puzzle.pieces[wrong].rotated(rotation).cells {
                let x = puzzle.x(of: clue.cell) - cell.x
                let y = puzzle.y(of: clue.cell) - cell.y
                if puzzle.check(wrong, at: FitPlacement(rotation: rotation, x: x, y: y), occupied: 0) == .clue(needs: clue.size) {
                    sawClue = true
                }
            }
        }
        _ = session
        #expect(sawClue)
    }

    @Test func anyCompleteFillCountsNotOnlyTheGeneratorsOwn() throws {
        // Level 2 is allowed more than one answer; every answer the solver finds must solve the session.
        let puzzle = FitGenerator.level(2)
        var answers: [[FitPlacement]] = []
        FitSolver.search(puzzle, keeping: Array(repeating: nil, count: puzzle.pieces.count)) { answer in
            answers.append(answer)
            return answers.count >= 5
        }
        #expect(!answers.isEmpty)
        for answer in answers {
            var session = FitSession(puzzle: puzzle)
            for piece in answer.indices {
                while session.rotations[piece] != answer[piece].rotation { session.rotate(piece) }
                session.place(piece, x: answer[piece].x, y: answer[piece].y)
            }
            #expect(session.isSolved)
        }
    }

    @Test func hintPlacesAPieceOrRemovesAWrongOne() throws {
        let puzzle = FitGenerator.daily(for: PuzzleDate(year: 2026, month: 11, day: 20))
        var session = FitSession(puzzle: puzzle)
        var hints = 0
        while !session.isSolved && hints < 30 {
            let hint = session.takeHint()
            #expect(hint != nil)
            hints += 1
        }
        #expect(session.isSolved)
        #expect(hints == puzzle.pieces.count)
        #expect(session.stars == 1)
    }

    @Test func snapshotRoundTripsAndRejectsOverlaps() throws {
        let puzzle = FitGenerator.daily(for: PuzzleDate(year: 2026, month: 11, day: 17))
        var session = FitSession(puzzle: puzzle)
        session.place(0, x: puzzle.solution[0].x, y: puzzle.solution[0].y)
        session.elapsed = 12.5
        let data = try JSONEncoder().encode(session.snapshot)
        let loaded = try JSONDecoder().decode(FitSession.Snapshot.self, from: data)
        let resumed = try #require(FitSession(puzzle: puzzle, snapshot: loaded))
        #expect(resumed.placements == session.placements)
        #expect(resumed.elapsed == 12.5)
        var both = loaded.placements
        both[1] = both[0]
        let overlapping = FitSession.Snapshot(placements: both, rotations: loaded.rotations, hintsUsed: 0, elapsed: 0)
        #expect(FitSession(puzzle: puzzle, snapshot: overlapping) == nil)
    }
}

@Suite struct FitSolverTests {
    /// Independent count: try every piece order and every placement.
    private func bruteForceCount(_ puzzle: FitPuzzle) -> Int {
        var count = 0
        func go(_ piece: Int, _ occupied: UInt64) {
            if piece == puzzle.pieces.count {
                if occupied == puzzle.outlineMask { count += 1 }
                return
            }
            for rotation in puzzle.allowedRotations(piece) {
                for y in -4..<puzzle.height {
                    for x in -4..<puzzle.width {
                        let placement = FitPlacement(rotation: rotation, x: x, y: y)
                        guard puzzle.check(piece, at: placement, occupied: occupied) == .fits,
                              let cells = puzzle.cells(of: piece, at: placement) else { continue }
                        var mask = occupied
                        for cell in cells { mask |= 1 << UInt64(cell) }
                        go(piece + 1, mask)
                    }
                }
            }
        }
        go(0, 0)
        return count
    }

    @Test func countMatchesBruteForceOnSmallPuzzles() {
        for level in 1...12 {
            let puzzle = FitGenerator.level(level)
            #expect(FitSolver.countSolutions(puzzle, limit: 1000) == bruteForceCount(puzzle), "level \(level)")
        }
    }
}

@Suite struct FitGeneratorTests {
    @Test func dailiesAreDeterministicDistinctAndValid() throws {
        var seen = Set<FitPuzzle>()
        for date in days(56) {
            let puzzle = FitGenerator.daily(for: date)
            #expect(puzzle == FitGenerator.daily(for: date))
            seen.insert(puzzle)
            let config = FitGenerator.config(for: date.weekday)
            #expect(config.cells.contains(puzzle.outlineCount), "\(date.iso) cells")
            #expect(puzzle.pieces.map(\.size).reduce(0, +) == puzzle.outlineCount)
            #expect(puzzle.pieces.allSatisfy { config.sizes.contains($0.size) })
            let answers = FitSolver.countSolutions(puzzle, limit: config.maxSolutions + 1)
            #expect(answers >= 1 && answers <= config.maxSolutions, "\(date.iso) has \(answers) answers")
            // The silhouette is a mirror image of itself.
            for y in 0..<puzzle.height {
                for x in 0..<puzzle.width {
                    #expect(puzzle.outline[puzzle.cell(x: x, y: y)] == puzzle.outline[puzzle.cell(x: puzzle.width - 1 - x, y: y)])
                }
            }
            // No two pieces look alike.
            let shapes = puzzle.pieces.map { $0.canonical(rotating: puzzle.rotates) }
            #expect(Set(shapes.map { "\($0)" }).count == shapes.count)
            // The generator's own answer is valid.
            var session = FitSession(puzzle: puzzle)
            for piece in puzzle.pieces.indices {
                while session.rotations[piece] != puzzle.solution[piece].rotation { session.rotate(piece) }
                session.place(piece, x: puzzle.solution[piece].x, y: puzzle.solution[piece].y)
            }
            #expect(session.isSolved, "\(date.iso)")
        }
        #expect(seen.count == 56)
    }

    @Test func earlyDaysDontRotateAndLaterDaysDo() {
        #expect(!FitGenerator.daily(for: PuzzleDate(year: 2026, month: 11, day: 16)).rotates)
        #expect(FitGenerator.daily(for: PuzzleDate(year: 2026, month: 11, day: 22)).rotates)
    }
}
