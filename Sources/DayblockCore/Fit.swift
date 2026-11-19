// Fit: fill an outline exactly with a set of block pieces. Some cells carry a
// number, which means "a piece of this many cells covers me". Boards are at
// most 64 cells, so a set of cells fits in one UInt64.

public struct FitCell: Hashable, Codable, Sendable, Comparable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public static func < (a: FitCell, b: FitCell) -> Bool { (a.y, a.x) < (b.y, b.x) }
}

/// A piece's shape, normalised so its top-left corner is at (0, 0).
public struct FitPiece: Hashable, Codable, Sendable {
    public let cells: [FitCell]

    public init(cells: [FitCell]) {
        let minX = cells.map(\.x).min() ?? 0
        let minY = cells.map(\.y).min() ?? 0
        self.cells = cells.map { FitCell(x: $0.x - minX, y: $0.y - minY) }.sorted()
    }

    public var size: Int { cells.count }
    public var width: Int { (cells.map(\.x).max() ?? 0) + 1 }
    public var height: Int { (cells.map(\.y).max() ?? 0) + 1 }

    /// The shape turned clockwise by `quarterTurns` quarter turns.
    public func rotated(_ quarterTurns: Int) -> FitPiece {
        var shape = self
        for _ in 0..<((quarterTurns % 4 + 4) % 4) {
            let h = shape.height
            shape = FitPiece(cells: shape.cells.map { FitCell(x: h - 1 - $0.y, y: $0.x) })
        }
        return shape
    }

    /// Rotations that give a different shape (1, 2 or 4 of them).
    public var distinctRotations: [Int] {
        var seen: [FitPiece] = []
        var turns: [Int] = []
        for turn in 0..<4 {
            let shape = rotated(turn)
            if !seen.contains(shape) {
                seen.append(shape)
                turns.append(turn)
            }
        }
        return turns
    }

    /// The same for every rotation of a shape, when rotations are allowed.
    public func canonical(rotating: Bool) -> [FitCell] {
        guard rotating else { return cells }
        return (0..<4).map { rotated($0).cells }.min { $0.lexicographicallyPrecedes($1) }!
    }
}

/// A cell that must be covered by a piece of `size` cells.
public struct FitClue: Hashable, Codable, Sendable {
    public let cell: Int
    public let size: Int

    public init(cell: Int, size: Int) {
        self.cell = cell
        self.size = size
    }
}

/// Where a piece sits: its rotation and the board position of its top-left corner.
public struct FitPlacement: Hashable, Codable, Sendable {
    public let rotation: Int
    public let x: Int
    public let y: Int

    public init(rotation: Int, x: Int, y: Int) {
        self.rotation = rotation
        self.x = x
        self.y = y
    }
}

public struct FitPuzzle: Hashable, Codable, Sendable {
    public let width: Int
    public let height: Int
    /// True for cells inside the outline.
    public let outline: [Bool]
    /// The pieces, stored the way they sit in the generator's own answer.
    public let pieces: [FitPiece]
    public let clues: [FitClue]
    /// Whether pieces may be turned. When false, pieces only fit as shown.
    public let rotates: Bool
    /// How each piece starts in the tray, in quarter turns from its answer orientation.
    public let trayRotations: [Int]
    /// The generator's own answer; any other complete fill is just as valid.
    public let solution: [FitPlacement]
    public let difficulty: Difficulty

    public init(width: Int, height: Int, outline: [Bool], pieces: [FitPiece], clues: [FitClue], rotates: Bool,
                trayRotations: [Int], solution: [FitPlacement], difficulty: Difficulty) {
        precondition(width * height <= 64 && outline.count == width * height, "fit boards hold at most 64 cells")
        precondition(pieces.count == trayRotations.count && pieces.count == solution.count, "one entry per piece")
        self.width = width
        self.height = height
        self.outline = outline
        self.pieces = pieces
        self.clues = clues
        self.rotates = rotates
        self.trayRotations = trayRotations
        self.solution = solution
        self.difficulty = difficulty
    }

    public var cellCount: Int { width * height }
    public var outlineCount: Int { outline.filter { $0 }.count }
    public var outlineMask: UInt64 {
        var mask: UInt64 = 0
        for cell in outline.indices where outline[cell] { mask |= 1 << UInt64(cell) }
        return mask
    }

    public func cell(x: Int, y: Int) -> Int { y * width + x }
    public func x(of cell: Int) -> Int { cell % width }
    public func y(of cell: Int) -> Int { cell / width }

    public func clueSize(at cell: Int) -> Int? { clues.first { $0.cell == cell }?.size }

    /// Board cells a piece would cover, or nil if any part falls off the board.
    public func cells(of piece: Int, at placement: FitPlacement) -> [Int]? {
        var result: [Int] = []
        for part in pieces[piece].rotated(placement.rotation).cells {
            let x = placement.x + part.x
            let y = placement.y + part.y
            guard x >= 0, y >= 0, x < width, y < height else { return nil }
            result.append(y * width + x)
        }
        return result
    }

    public enum PlacementCheck: Equatable, Sendable {
        case fits
        /// Part of the piece is outside the outline.
        case outside
        /// The piece overlaps one already placed.
        case overlap
        /// The piece covers a number it doesn't match.
        case clue(needs: Int)
    }

    /// Whether a piece can go at `placement`, given the cells already covered.
    public func check(_ piece: Int, at placement: FitPlacement, occupied: UInt64) -> PlacementCheck {
        guard let cells = cells(of: piece, at: placement) else { return .outside }
        if cells.contains(where: { !outline[$0] }) { return .outside }
        if cells.contains(where: { occupied & (1 << UInt64($0)) != 0 }) { return .overlap }
        let size = pieces[piece].size
        if let clue = clues.first(where: { cells.contains($0.cell) && $0.size != size }) {
            return .clue(needs: clue.size)
        }
        return .fits
    }

    /// Rotations the player can use for a piece.
    public func allowedRotations(_ piece: Int) -> [Int] {
        rotates ? pieces[piece].distinctRotations : [0]
    }
}

/// One play-through of a Fit puzzle. There is no move count: pieces can be
/// picked up and put down freely. Stars come from hints.
public struct FitSession: Sendable {
    public struct Snapshot: Codable, Equatable, Sendable {
        public let placements: [FitPlacement?]
        public let rotations: [Int]
        public let hintsUsed: Int
        public let elapsed: Double
    }

    public enum HintResult: Equatable, Sendable {
        /// A piece was put where an answer needs it.
        case placed(piece: Int)
        /// A piece already on the board can't be part of any answer, so it went back.
        case removed(piece: Int)
    }

    public let puzzle: FitPuzzle
    /// Where each piece is, or nil while it is still in the tray.
    public private(set) var placements: [FitPlacement?]
    /// Each piece's current rotation, in quarter turns from its answer orientation.
    public private(set) var rotations: [Int]
    public private(set) var hintsUsed = 0
    /// Seconds spent with the puzzle on screen. The app adds to it.
    public var elapsed: Double = 0

    public init(puzzle: FitPuzzle) {
        self.puzzle = puzzle
        placements = Array(repeating: nil, count: puzzle.pieces.count)
        rotations = puzzle.rotates ? puzzle.trayRotations : Array(repeating: 0, count: puzzle.pieces.count)
    }

    /// Resumes a saved play. Returns nil if the snapshot doesn't fit this puzzle.
    public init?(puzzle: FitPuzzle, snapshot: Snapshot) {
        guard snapshot.placements.count == puzzle.pieces.count, snapshot.rotations.count == puzzle.pieces.count,
              snapshot.hintsUsed >= 0, snapshot.elapsed >= 0, snapshot.elapsed.isFinite
        else { return nil }
        var session = FitSession(puzzle: puzzle)
        for piece in puzzle.pieces.indices {
            let rotation = (snapshot.rotations[piece] % 4 + 4) % 4
            if !puzzle.rotates && rotation != 0 { return nil }
            session.rotations[piece] = rotation
            if let placement = snapshot.placements[piece] {
                guard puzzle.check(piece, at: placement, occupied: session.occupied) == .fits else { return nil }
                session.placements[piece] = placement
            }
        }
        session.hintsUsed = snapshot.hintsUsed
        session.elapsed = snapshot.elapsed
        self = session
    }

    public var snapshot: Snapshot {
        Snapshot(placements: placements, rotations: rotations, hintsUsed: hintsUsed, elapsed: elapsed)
    }

    /// Every board cell currently covered.
    public var occupied: UInt64 {
        var mask: UInt64 = 0
        for piece in placements.indices {
            guard let placement = placements[piece], let cells = puzzle.cells(of: piece, at: placement) else { continue }
            for cell in cells { mask |= 1 << UInt64(cell) }
        }
        return mask
    }

    /// Which piece covers each cell, or nil.
    public var coverage: [Int?] {
        var result = [Int?](repeating: nil, count: puzzle.cellCount)
        for piece in placements.indices {
            guard let placement = placements[piece], let cells = puzzle.cells(of: piece, at: placement) else { continue }
            for cell in cells { result[cell] = piece }
        }
        return result
    }

    public var isSolved: Bool { placements.allSatisfy { $0 != nil } }
    public var placedCount: Int { placements.compactMap { $0 }.count }

    /// 3 stars with no hints, 2 with one, 1 with more.
    public var stars: Int? {
        guard isSolved else { return nil }
        return hintsUsed == 0 ? 3 : hintsUsed == 1 ? 2 : 1
    }

    /// Checks a move without making it. A piece being moved doesn't block itself.
    public func check(_ piece: Int, x: Int, y: Int) -> FitPuzzle.PlacementCheck {
        var occupied = self.occupied
        if let current = placements[piece], let cells = puzzle.cells(of: piece, at: current) {
            for cell in cells { occupied &= ~(1 << UInt64(cell)) }
        }
        return puzzle.check(piece, at: FitPlacement(rotation: rotations[piece], x: x, y: y), occupied: occupied)
    }

    /// Puts a piece (from the tray, or moved from elsewhere on the board) at x, y.
    @discardableResult
    public mutating func place(_ piece: Int, x: Int, y: Int) -> FitPuzzle.PlacementCheck {
        guard !isSolved else { return .overlap }
        let result = check(piece, x: x, y: y)
        if result == .fits { placements[piece] = FitPlacement(rotation: rotations[piece], x: x, y: y) }
        return result
    }

    /// Sends a placed piece back to the tray.
    public mutating func remove(_ piece: Int) {
        guard !isSolved else { return }
        placements[piece] = nil
    }

    /// Turns a piece a quarter turn clockwise. Tray pieces turn in place. A
    /// piece on the board stays put when the new turn still fits at the same
    /// corner; otherwise it goes back to the tray already turned.
    public mutating func rotate(_ piece: Int) {
        guard puzzle.rotates, !isSolved else { return }
        if let placement = placements[piece] {
            let next = (placement.rotation + 1) % 4
            placements[piece] = nil
            rotations[piece] = next
            if check(piece, x: placement.x, y: placement.y) == .fits {
                placements[piece] = FitPlacement(rotation: next, x: placement.x, y: placement.y)
            }
        } else {
            rotations[piece] = (rotations[piece] + 1) % 4
        }
    }

    /// Sends every piece back to the tray.
    public mutating func clear() {
        guard !isSolved else { return }
        placements = Array(repeating: nil, count: puzzle.pieces.count)
    }

    /// A legal placement of `piece` that covers board cell `cell`, if any.
    /// Tries each part of the piece under the tapped cell so select-then-tap play works.
    public func placementCovering(_ piece: Int, cell: Int) -> FitPlacement? {
        guard puzzle.outline.indices.contains(cell), puzzle.outline[cell] else { return nil }
        let px = puzzle.x(of: cell), py = puzzle.y(of: cell)
        let shape = puzzle.pieces[piece].rotated(rotations[piece])
        for part in shape.cells {
            let x = px - part.x, y = py - part.y
            if check(piece, x: x, y: y) == .fits {
                return FitPlacement(rotation: rotations[piece], x: x, y: y)
            }
        }
        return nil
    }

    /// Every spot where a piece fits right now, for VoiceOver and Switch Control.
    public func fittingSpots(_ piece: Int) -> [FitPlacement] {
        var spots: [FitPlacement] = []
        for y in 0..<puzzle.height {
            for x in 0..<puzzle.width where check(piece, x: x, y: y) == .fits {
                spots.append(FitPlacement(rotation: rotations[piece], x: x, y: y))
            }
        }
        return spots
    }

    /// Places one piece where an answer needs it, keeping the player's correct
    /// pieces. If the pieces already down can't be part of any answer, sends one back.
    public mutating func takeHint() -> HintResult? {
        guard !isSolved else { return nil }
        if let answer = FitSolver.firstSolution(puzzle, keeping: placements) {
            // Prefer the biggest unplaced piece: it settles the most.
            let unplaced = placements.indices.filter { placements[$0] == nil }
            guard let piece = unplaced.max(by: { puzzle.pieces[$0].size < puzzle.pieces[$1].size }) else { return nil }
            placements[piece] = answer[piece]
            rotations[piece] = answer[piece].rotation
            hintsUsed += 1
            return .placed(piece: piece)
        }
        // Something on the board is wrong. Send back the first piece whose
        // removal makes the board solvable again.
        for piece in placements.indices where placements[piece] != nil {
            var trial = placements
            trial[piece] = nil
            if FitSolver.firstSolution(puzzle, keeping: trial) != nil {
                placements[piece] = nil
                hintsUsed += 1
                return .removed(piece: piece)
            }
        }
        // Several pieces are wrong together: start that piece over.
        if let piece = placements.indices.first(where: { placements[$0] != nil }) {
            placements[piece] = nil
            hintsUsed += 1
            return .removed(piece: piece)
        }
        return nil
    }
}

extension FitPuzzle {
    /// Text picture of the answer: a letter per piece, digits for clues, . outside.
    public func render() -> String {
        var grid = [String](repeating: " .", count: cellCount)
        let letters = Array("ABCDEFGHIJKLMNOP")
        for piece in pieces.indices {
            guard let cells = cells(of: piece, at: solution[piece]) else { continue }
            for cell in cells { grid[cell] = " " + String(letters[piece % letters.count]) }
        }
        for clue in clues { grid[clue.cell] = String(grid[clue.cell].dropFirst()).lowercased() + String(clue.size) }
        var lines: [String] = []
        for y in 0..<height { lines.append(grid[(y * width)..<((y + 1) * width)].joined(separator: " ")) }
        return lines.joined(separator: "\n")
    }
}

public enum FitSolver {
    /// Every legal placement of every piece, indexed by each cell it covers.
    static func prepare(_ puzzle: FitPuzzle) -> [[[(UInt64, FitPlacement)]]] {
        var byCell = Array(repeating: Array(repeating: [(UInt64, FitPlacement)](), count: puzzle.cellCount),
                           count: puzzle.pieces.count)
        for piece in puzzle.pieces.indices {
            for rotation in puzzle.allowedRotations(piece) {
                let shape = puzzle.pieces[piece].rotated(rotation)
                guard shape.height <= puzzle.height, shape.width <= puzzle.width else { continue }
                for y in 0...(puzzle.height - shape.height) {
                    for x in 0...(puzzle.width - shape.width) {
                        let placement = FitPlacement(rotation: rotation, x: x, y: y)
                        guard puzzle.check(piece, at: placement, occupied: 0) == .fits,
                              let cells = puzzle.cells(of: piece, at: placement) else { continue }
                        var mask: UInt64 = 0
                        for cell in cells { mask |= 1 << UInt64(cell) }
                        for cell in cells { byCell[piece][cell].append((mask, placement)) }
                    }
                }
            }
        }
        return byCell
    }

    /// Counts complete fills, stopping once `limit` is reached.
    public static func countSolutions(_ puzzle: FitPuzzle, limit: Int) -> Int {
        var count = 0
        search(puzzle, keeping: Array(repeating: nil, count: puzzle.pieces.count)) { _ in
            count += 1
            return count >= limit
        }
        return count
    }

    /// One complete fill that keeps the given placements, or nil if there is none.
    public static func firstSolution(_ puzzle: FitPuzzle, keeping fixed: [FitPlacement?]) -> [FitPlacement]? {
        var found: [FitPlacement]?
        search(puzzle, keeping: fixed) { solution in
            found = solution
            return true
        }
        return found
    }

    /// Exact-cover search: always fill the lowest empty cell first.
    /// `visit` returns true to stop.
    static func search(_ puzzle: FitPuzzle, keeping fixed: [FitPlacement?], visit: ([FitPlacement]) -> Bool) {
        let byCell = prepare(puzzle)
        let goal = puzzle.outlineMask
        var occupied: UInt64 = 0
        var chosen = fixed
        for piece in fixed.indices {
            guard let placement = fixed[piece] else { continue }
            guard puzzle.check(piece, at: placement, occupied: occupied) == .fits,
                  let cells = puzzle.cells(of: piece, at: placement) else { return }
            for cell in cells { occupied |= 1 << UInt64(cell) }
        }
        var stop = false
        func recurse() {
            if stop { return }
            let empty = goal & ~occupied
            if empty == 0 {
                stop = visit(chosen.map { $0! })
                return
            }
            let cell = empty.trailingZeroBitCount
            for piece in chosen.indices where chosen[piece] == nil {
                for (mask, placement) in byCell[piece][cell] where mask & occupied == 0 {
                    chosen[piece] = placement
                    occupied |= mask
                    recurse()
                    occupied &= ~mask
                    chosen[piece] = nil
                    if stop { return }
                }
            }
        }
        recurse()
    }
}
