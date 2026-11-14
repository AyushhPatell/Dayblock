public enum Difficulty: String, Codable, CaseIterable, Sendable {
    case easy, medium, hard, expert
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

    public init(
        board: Board, colorStarts: [Int], targets: [Int], greyStarts: [Int],
        difficulty: Difficulty, par: Int, solution: [Direction]
    ) {
        precondition(colorStarts.count == targets.count, "one target per coloured block")
        self.board = board
        self.colorStarts = colorStarts
        self.targets = targets
        self.greyStarts = greyStarts
        self.difficulty = difficulty
        self.par = par
        self.solution = solution
    }

    public var colorCount: Int { colorStarts.count }
    public var startPositions: [Int] { colorStarts + greyStarts }

    public func isSolved(_ positions: [Int]) -> Bool {
        for colour in 0..<targets.count where positions[colour] != targets[colour] { return false }
        return true
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
