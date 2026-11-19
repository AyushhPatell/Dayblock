// Paint: one block slides until something stops it, painting every cell it
// crosses. The puzzle is solved when every floor cell is painted, and the
// score is how few swipes it took.
//
// Boards are at most 7×7, so the set of painted cells fits in one UInt64.

/// The fixed part of a Paint puzzle: which cells are floor, and which floor
/// cells are sticky pads that stop the block when it enters them.
public struct PaintBoard: Hashable, Sendable {
    public let width: Int
    public let height: Int
    /// True for floor cells. Other cells are solid blocks the paint block can't enter.
    public let open: [Bool]
    /// True for floor cells that stop the block on entry.
    public let pads: [Bool]
    /// Every floor cell, as a bit mask.
    public let floorMask: UInt64
    /// For each cell and direction (cell * 4 + direction): where the block stops.
    let destinations: [Int]
    /// For each cell and direction: the cells painted on the way, including the stop.
    let paths: [UInt64]

    public init(width: Int, height: Int, open: [Bool], pads: [Bool]) {
        precondition(width > 0 && height > 0 && width * height <= 58, "paint boards hold at most 58 cells")
        precondition(open.count == width * height && pads.count == width * height, "one entry per cell")
        self.width = width
        self.height = height
        self.open = open
        self.pads = zip(open, pads).map { $0 && $1 }
        var floor: UInt64 = 0
        for cell in open.indices where open[cell] { floor |= 1 << UInt64(cell) }
        floorMask = floor

        var destinations = [Int](repeating: 0, count: width * height * 4)
        var paths = [UInt64](repeating: 0, count: width * height * 4)
        for cell in 0..<(width * height) {
            for direction in Direction.allCases {
                var at = cell
                var painted: UInt64 = 0
                if open[cell] {
                    while let next = Self.neighbour(of: at, direction, width: width, height: height), open[next] {
                        at = next
                        painted |= 1 << UInt64(at)
                        if self.pads[at] { break }
                    }
                }
                destinations[cell * 4 + Int(direction.rawValue)] = at
                paths[cell * 4 + Int(direction.rawValue)] = painted
            }
        }
        self.destinations = destinations
        self.paths = paths
    }

    public var cellCount: Int { width * height }
    public var floorCount: Int { floorMask.nonzeroBitCount }
    public func cell(x: Int, y: Int) -> Int { y * width + x }
    public func x(of cell: Int) -> Int { cell % width }
    public func y(of cell: Int) -> Int { cell / width }

    static func neighbour(of cell: Int, _ direction: Direction, width: Int, height: Int) -> Int? {
        let x = cell % width
        let y = cell / width
        switch direction {
        case .up: return y > 0 ? cell - width : nil
        case .down: return y < height - 1 ? cell + width : nil
        case .left: return x > 0 ? cell - 1 : nil
        case .right: return x < width - 1 ? cell + 1 : nil
        }
    }

    /// Where the block stops when it leaves `cell` in `direction`, and what it paints.
    /// The destination equals `cell` when the block can't move that way.
    public func move(from cell: Int, _ direction: Direction) -> (to: Int, painted: UInt64) {
        let index = cell * 4 + Int(direction.rawValue)
        return (destinations[index], paths[index])
    }

    /// The cells crossed on the way, in order, ending at the stop.
    public func pathCells(from cell: Int, _ direction: Direction) -> [Int] {
        var cells: [Int] = []
        var at = cell
        let stop = move(from: cell, direction).to
        while at != stop, let next = Self.neighbour(of: at, direction, width: width, height: height) {
            at = next
            cells.append(at)
        }
        return cells
    }
}

extension PaintBoard: Codable {
    private enum CodingKeys: String, CodingKey { case width, height, open, pads }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let width = try container.decode(Int.self, forKey: .width)
        let height = try container.decode(Int.self, forKey: .height)
        let open = try container.decode([Bool].self, forKey: .open)
        let pads = try container.decode([Bool].self, forKey: .pads)
        guard width > 0, height > 0, width * height <= 58, open.count == width * height, pads.count == open.count else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad paint board"))
        }
        self.init(width: width, height: height, open: open, pads: pads)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(open, forKey: .open)
        try container.encode(pads, forKey: .pads)
    }
}

/// One Paint puzzle.
public struct PaintPuzzle: Hashable, Codable, Sendable {
    public let board: PaintBoard
    public let start: Int
    public let difficulty: Difficulty
    /// The fewest swipes that paint every floor cell.
    public let par: Int
    /// One shortest solution.
    public let solution: [Direction]

    public init(board: PaintBoard, start: Int, difficulty: Difficulty, par: Int, solution: [Direction]) {
        self.board = board
        self.start = start
        self.difficulty = difficulty
        self.par = par
        self.solution = solution
    }

    /// The start cell is painted before the first swipe.
    public var startMask: UInt64 { 1 << UInt64(start) }

    /// 3 stars at par; 2 within a small margin that grows with the puzzle; else 1.
    public func stars(forSwipes swipes: Int) -> Int {
        if swipes <= par { return 3 }
        if swipes <= par + max(2, par / 4) { return 2 }
        return 1
    }

    /// Text picture: # solid, o pad, S start.
    public func render() -> String {
        var lines: [String] = []
        for y in 0..<board.height {
            var row = ""
            for x in 0..<board.width {
                let cell = board.cell(x: x, y: y)
                if !board.open[cell] { row += "##" }
                else if cell == start { row += "S " }
                else if board.pads[cell] { row += "o " }
                else { row += ". " }
            }
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }
}

/// One play-through of a Paint puzzle. Undo gives the swipe back: the score
/// is the length of the route on the board, not every attempt.
public struct PaintSession: Sendable {
    public struct Step: Codable, Equatable, Sendable {
        public let position: Int
        public let painted: UInt64
    }

    public struct Snapshot: Codable, Equatable, Sendable {
        public let route: [Step]
        public let hintsUsed: Int
    }

    public struct SwipeResult: Equatable, Sendable {
        public let direction: Direction
        public let from: Int
        public let to: Int
        /// Cells crossed in order, ending at the stop.
        public let path: [Int]
        /// Cells that were unpainted before this swipe.
        public let newlyPainted: [Int]
        public let solved: Bool
    }

    public let puzzle: PaintPuzzle
    /// Every resting point so far, starting with the start cell.
    public private(set) var route: [Step]
    public private(set) var hintsUsed = 0

    public init(puzzle: PaintPuzzle) {
        self.puzzle = puzzle
        route = [Step(position: puzzle.start, painted: puzzle.startMask)]
    }

    /// Resumes a saved play. Returns nil if the snapshot doesn't fit this puzzle.
    public init?(puzzle: PaintPuzzle, snapshot: Snapshot) {
        guard let first = snapshot.route.first, first.position == puzzle.start,
              first.painted == puzzle.startMask, snapshot.hintsUsed >= 0
        else { return nil }
        // Replay-check every step, so a corrupt save can't put the block somewhere impossible.
        for (previous, step) in zip(snapshot.route, snapshot.route.dropFirst()) {
            let fits = Direction.allCases.contains { direction in
                let move = puzzle.board.move(from: previous.position, direction)
                return move.to == step.position && move.to != previous.position
                    && previous.painted | move.painted == step.painted
            }
            guard fits else { return nil }
        }
        self.puzzle = puzzle
        route = snapshot.route
        hintsUsed = snapshot.hintsUsed
    }

    public var snapshot: Snapshot { Snapshot(route: route, hintsUsed: hintsUsed) }
    public var position: Int { route[route.count - 1].position }
    public var painted: UInt64 { route[route.count - 1].painted }
    public var swipeCount: Int { route.count - 1 }
    public var cellsLeft: Int { (puzzle.board.floorMask & ~painted).nonzeroBitCount }
    public var isSolved: Bool { painted == puzzle.board.floorMask }
    public var canUndo: Bool { swipeCount > 0 && !isSolved }

    public func isPainted(_ cell: Int) -> Bool { painted & (1 << UInt64(cell)) != 0 }

    /// Stars for a finished puzzle. Any hint caps the result at two stars.
    public var stars: Int? {
        guard isSolved else { return nil }
        let earned = puzzle.stars(forSwipes: swipeCount)
        return hintsUsed > 0 ? min(earned, 2) : earned
    }

    @discardableResult
    public mutating func swipe(_ direction: Direction) -> SwipeResult? {
        guard !isSolved else { return nil }
        let from = position
        let move = puzzle.board.move(from: from, direction)
        guard move.to != from else { return nil }
        let before = painted
        let after = before | move.painted
        route.append(Step(position: move.to, painted: after))
        let path = puzzle.board.pathCells(from: from, direction)
        let fresh = path.filter { before & (1 << UInt64($0)) == 0 }
        return SwipeResult(direction: direction, from: from, to: move.to, path: path,
                           newlyPainted: fresh, solved: after == puzzle.board.floorMask)
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard canUndo else { return false }
        route.removeLast()
        return true
    }

    public mutating func restart() {
        guard !isSolved else { return }
        route = [route[0]]
    }

    /// The next swipe on a shortest route from here. Records that a hint was used.
    public mutating func takeHint() -> Direction? {
        guard !isSolved, let next = PaintSolver.solve(puzzle.board, from: position, painted: painted)?.first else {
            return nil
        }
        hintsUsed += 1
        return next
    }
}

public enum PaintSolver {
    /// A shortest list of swipes that paints every floor cell, or nil if none
    /// is found within `maxNodes` explored positions.
    public static func solve(
        _ board: PaintBoard, from start: Int, painted startPainted: UInt64, maxNodes: Int = 400_000
    ) -> [Direction]? {
        let goal = board.floorMask
        if startPainted == goal { return [] }
        // State: painted mask (up to 58 bits) shifted left 6, plus the position.
        func key(_ position: Int, _ painted: UInt64) -> UInt64 { painted << 6 | UInt64(position) }
        var keys: [UInt64] = [key(start, startPainted)]
        var parents: [Int32] = [-1]
        var moves: [UInt8] = [0]
        var seen: Set<UInt64> = [keys[0]]
        var head = 0
        while head < keys.count {
            let current = keys[head]
            let position = Int(current & 63)
            let painted = current >> 6
            for direction in Direction.allCases {
                let move = board.move(from: position, direction)
                if move.to == position { continue }
                let nextPainted = painted | move.painted
                let next = key(move.to, nextPainted)
                guard seen.insert(next).inserted else { continue }
                keys.append(next)
                parents.append(Int32(head))
                moves.append(direction.rawValue)
                if nextPainted == goal {
                    var path: [Direction] = []
                    var node = keys.count - 1
                    while parents[node] >= 0 {
                        path.append(Direction(rawValue: moves[node])!)
                        node = Int(parents[node])
                    }
                    return path.reversed()
                }
                if keys.count >= maxNodes { return nil }
            }
            head += 1
        }
        return nil
    }

    public static func solve(_ puzzle: PaintPuzzle) -> [Direction]? {
        solve(puzzle.board, from: puzzle.start, painted: puzzle.startMask)
    }

    /// Every cell the block can rest on, starting from `start`.
    static func restingCells(_ board: PaintBoard, from start: Int) -> [Int] {
        var seen: Set<Int> = [start]
        var queue = [start]
        var head = 0
        while head < queue.count {
            let cell = queue[head]
            head += 1
            for direction in Direction.allCases {
                let to = board.move(from: cell, direction).to
                if to != cell, seen.insert(to).inserted { queue.append(to) }
            }
        }
        return queue
    }

    /// True when the player can never get stuck: from every resting cell the
    /// block can get back to every other, and together the moves can paint the
    /// whole floor. Then every position, however painted, can still be finished.
    public static func isAlwaysFinishable(_ board: PaintBoard, start: Int) -> Bool {
        let resting = restingCells(board, from: start)
        var coverage: UInt64 = 1 << UInt64(start)
        for cell in resting {
            for direction in Direction.allCases { coverage |= board.move(from: cell, direction).painted }
            // Strong connectivity: every resting cell must reach the start again.
            if !restingCells(board, from: cell).contains(start) { return false }
        }
        return coverage == board.floorMask
    }
}
