public enum Difficulty: String, Codable, CaseIterable, Sendable {
    case easy, medium, hard, expert
}

/// How a puzzle is played. Missing data from older saves means `.classic`.
public struct Rules: Codable, Hashable, Sendable {
    /// A coloured block that comes to rest on its own target never moves again.
    public var locksOnTarget: Bool
    /// Undo removes that swipe from the count, and restart clears the route.
    public var undoRefundsSwipes: Bool

    public init(locksOnTarget: Bool, undoRefundsSwipes: Bool) {
        self.locksOnTarget = locksOnTarget
        self.undoRefundsSwipes = undoRefundsSwipes
    }

    /// Today's rules: nothing locks, and every swipe counts.
    public static let classic = Rules(locksOnTarget: false, undoRefundsSwipes: false)
    /// Practice experiment: parked blocks stay, and undo gives the swipe back.
    public static let locking = Rules(locksOnTarget: true, undoRefundsSwipes: true)
}

/// One Tilt puzzle. Block order is always: coloured blocks first (colour 0, 1, …),
/// then grey blocks. Grey blocks slide like any other but have no target.
public struct Puzzle: Hashable, Codable, Sendable {
    public let board: Board
    /// Starting cell of each coloured block, indexed by colour.
    public let colorStarts: [Int]
    /// Target cell of each coloured block, indexed by colour.
    public let targets: [Int]
    public let greyStarts: [Int]
    public let difficulty: Difficulty
    /// The fewest swipes that solve the puzzle.
    public let par: Int
    /// One shortest solution.
    public let solution: [Direction]
    public let rules: Rules

    public init(
        board: Board, colorStarts: [Int], targets: [Int], greyStarts: [Int],
        difficulty: Difficulty, par: Int, solution: [Direction], rules: Rules = .classic
    ) {
        precondition(colorStarts.count == targets.count, "one target per coloured block")
        self.board = board
        self.colorStarts = colorStarts
        self.targets = targets
        self.greyStarts = greyStarts
        self.difficulty = difficulty
        self.par = par
        self.solution = solution
        self.rules = rules
    }

    public var colorCount: Int { colorStarts.count }
    public var startPositions: [Int] { colorStarts + greyStarts }

    public func isSolved(_ positions: [Int]) -> Bool {
        for colour in 0..<targets.count where positions[colour] != targets[colour] { return false }
        return true
    }

    /// True when this coloured block is on its target and the lock rule will keep it there.
    public func isLocked(_ positions: [Int], block: Int) -> Bool {
        rules.locksOnTarget && block >= 0 && block < colorCount && block < positions.count
            && positions[block] == targets[block]
    }

    /// Slides under this puzzle's rules. Locked blocks stay put and act as walls.
    public func slide(_ positions: [Int], _ direction: Direction) -> [Int] {
        guard rules.locksOnTarget else { return board.slide(positions, direction) }
        var fixed = [Bool](repeating: false, count: positions.count)
        let limit = min(colorCount, positions.count, targets.count)
        for index in 0..<limit where positions[index] == targets[index] {
            fixed[index] = true
        }
        return board.slide(positions, direction, fixed: fixed)
    }

    /// 3 stars for matching the best possible, 2 for up to two extra swipes, else 1.
    public func stars(forSwipes swipes: Int) -> Int {
        if swipes <= par { return 3 }
        if swipes <= par + 2 { return 2 }
        return 1
    }

    /// Plain-text picture of the board. Capital letter = coloured block,
    /// lowercase = that colour's target, # = grey block.
    public func render(_ positions: [Int]? = nil) -> String {
        let positions = positions ?? startPositions
        let letters = Array("ABCDEFGH")
        var lines: [String] = []
        lines.append("+" + String(repeating: "--+", count: board.width))
        for y in 0..<board.height {
            var row = "|"
            var below = "+"
            for x in 0..<board.width {
                let cell = board.cell(x: x, y: y)
                var first: Character = " "
                var second: Character = " "
                if let index = positions.firstIndex(of: cell) {
                    first = index < colorCount ? letters[index] : "#"
                }
                if let colour = targets.firstIndex(of: cell) {
                    second = Character(String(letters[colour]).lowercased())
                }
                row += String([first, second])
                row += board.isBlocked(cell, .right) ? "|" : " "
                below += board.isBlocked(cell, .down) ? "--+" : "  +"
            }
            lines.append(row)
            lines.append(below)
        }
        return lines.joined(separator: "\n")
    }
}

extension Puzzle {
    private enum CodingKeys: String, CodingKey {
        case board, colorStarts, targets, greyStarts, difficulty, par, solution, rules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            board: try container.decode(Board.self, forKey: .board),
            colorStarts: try container.decode([Int].self, forKey: .colorStarts),
            targets: try container.decode([Int].self, forKey: .targets),
            greyStarts: try container.decode([Int].self, forKey: .greyStarts),
            difficulty: try container.decode(Difficulty.self, forKey: .difficulty),
            par: try container.decode(Int.self, forKey: .par),
            solution: try container.decode([Direction].self, forKey: .solution),
            rules: try container.decodeIfPresent(Rules.self, forKey: .rules) ?? .classic
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(board, forKey: .board)
        try container.encode(colorStarts, forKey: .colorStarts)
        try container.encode(targets, forKey: .targets)
        try container.encode(greyStarts, forKey: .greyStarts)
        try container.encode(difficulty, forKey: .difficulty)
        try container.encode(par, forKey: .par)
        try container.encode(solution, forKey: .solution)
        try container.encode(rules, forKey: .rules)
    }
}
