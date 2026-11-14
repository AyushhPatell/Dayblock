/// One play-through of a puzzle: where the blocks are and how many swipes were used.
public struct GameSession: Sendable {
    public struct BlockMove: Equatable, Sendable {
        /// Index into `positions` (coloured blocks first, then grey).
        public let block: Int
        public let from: Int
        public let to: Int

        public init(block: Int, from: Int, to: Int) {
            self.block = block
            self.from = from
            self.to = to
        }
    }

    public struct SwipeResult: Equatable, Sendable {
        public let direction: Direction
        /// Only the blocks that actually moved.
        public let moves: [BlockMove]
        public let solved: Bool
    }

    public let puzzle: Puzzle
    public private(set) var positions: [Int]
    /// Every swipe that moved something, including ones later undone.
    public private(set) var swipeCount = 0
    private var history: [[Int]] = []

    /// Everything needed to resume a play-through later.
    public struct Snapshot: Codable, Equatable, Sendable {
        public let positions: [Int]
        public let swipeCount: Int
        public let history: [[Int]]

        /// The same snapshot without its undo steps. A solved puzzle can't be
        /// undone, so there is no reason to keep them in the save file.
        public func droppingHistory() -> Snapshot {
            Snapshot(positions: positions, swipeCount: swipeCount, history: [])
        }
    }

    public init(puzzle: Puzzle) {
        self.puzzle = puzzle
        self.positions = puzzle.startPositions
    }

    /// Resumes from a saved snapshot. Returns nil if the snapshot does not fit
    /// this puzzle (for example, it was saved for a different one).
    public init?(puzzle: Puzzle, snapshot: Snapshot) {
        let count = puzzle.startPositions.count
        let cells = 0..<puzzle.board.cellCount
        func fits(_ p: [Int]) -> Bool {
            p.count == count && Set(p).count == count && p.allSatisfy(cells.contains)
        }
        guard fits(snapshot.positions), snapshot.history.allSatisfy(fits), snapshot.swipeCount >= 0 else {
            return nil
        }
        self.puzzle = puzzle
        self.positions = snapshot.positions
        self.swipeCount = snapshot.swipeCount
        self.history = snapshot.history
    }

    public var snapshot: Snapshot {
        Snapshot(positions: positions, swipeCount: swipeCount, history: history)
    }

    public var isSolved: Bool { puzzle.isSolved(positions) }
    public var canUndo: Bool { !history.isEmpty && !isSolved }
    public var stars: Int? { isSolved ? puzzle.stars(forSwipes: swipeCount) : nil }

    /// Tilts the board. Returns nil, and counts nothing, when no block moves
    /// or the puzzle is already solved.
    @discardableResult
    public mutating func swipe(_ direction: Direction) -> SwipeResult? {
        guard !isSolved else { return nil }
        let next = puzzle.board.slide(positions, direction)
        guard next != positions else { return nil }
        var moves: [BlockMove] = []
        for block in positions.indices where positions[block] != next[block] {
            moves.append(BlockMove(block: block, from: positions[block], to: next[block]))
        }
        history.append(positions)
        positions = next
        swipeCount += 1
        return SwipeResult(direction: direction, moves: moves, solved: isSolved)
    }

    /// Steps back one swipe. The swipe count is not refunded.
    @discardableResult
    public mutating func undo() -> Bool {
        guard canUndo, let previous = history.popLast() else { return false }
        positions = previous
        return true
    }

    /// Puts the blocks back at the start. The swipe count is kept.
    public mutating func restart() {
        guard !isSolved else { return }
        positions = puzzle.startPositions
        history.removeAll()
    }

    /// Adds one swipe to the count without moving anything. Used when a hint
    /// is taken in the daily puzzle, so help always costs something.
    public mutating func addPenaltySwipe() {
        guard !isSolved else { return }
        swipeCount += 1
    }

    /// The next swipe on a shortest route to the solution from here.
    public func hint() -> Direction? {
        Solver.solve(puzzle, from: positions)?.moves.first
    }
}
