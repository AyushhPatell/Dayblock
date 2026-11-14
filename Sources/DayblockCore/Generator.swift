/// Small, fast random source with a fixed algorithm (SplitMix64), so the
/// same seed gives the same puzzle on every device and Swift version.
public struct SeededRandom: Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform-enough integer in 0..<bound.
    public mutating func int(below bound: Int) -> Int {
        precondition(bound > 0)
        return Int(next() % UInt64(bound))
    }

    public mutating func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + int(below: range.count)
    }
}

public enum Generator {
    /// Changing the generator changes every daily puzzle. Bump this only
    /// before launch, or keep old versions selectable.
    public static let version = 1

    struct Config {
        let size: Int
        let colors: Int
        let greys: ClosedRange<Int>
        let walls: ClosedRange<Int>
        let par: ClosedRange<Int>
    }

    static func config(for difficulty: Difficulty) -> Config {
        switch difficulty {
        case .easy: return Config(size: 5, colors: 2, greys: 0...1, walls: 3...5, par: 4...5)
        case .medium: return Config(size: 5, colors: 3, greys: 1...1, walls: 3...5, par: 6...7)
        case .hard: return Config(size: 6, colors: 3, greys: 1...2, walls: 5...8, par: 8...10)
        case .expert: return Config(size: 6, colors: 4, greys: 1...2, walls: 5...8, par: 10...13)
        }
    }

    public static func difficulty(for weekday: PuzzleDate.Weekday) -> Difficulty {
        switch weekday {
        case .monday, .tuesday: return .easy
        case .wednesday, .thursday: return .medium
        case .friday, .saturday: return .hard
        case .sunday: return .expert
        }
    }

    /// The daily puzzle: the same for everyone on a given date.
    public static func daily(for date: PuzzleDate) -> Puzzle {
        generate(seed: hash("dayblock-tilt-v\(version)-\(date.iso)"), difficulty: difficulty(for: date.weekday))
    }

    /// A practice puzzle from any seed.
    public static func practice(seed: UInt64, difficulty: Difficulty) -> Puzzle {
        generate(seed: hash("dayblock-tilt-practice-v\(version)") ^ seed &* 0x2545_F491_4F6C_DD1D, difficulty: difficulty)
    }

    public static func generate(seed: UInt64, difficulty: Difficulty) -> Puzzle {
        let config = config(for: difficulty)
        var attempt: UInt64 = 0
        var minPar = config.par.lowerBound
        while true {
            // Loosen the lower bound a little if a seed is unlucky, so this always ends.
            for _ in 0..<40 {
                var random = SeededRandom(seed: seed &+ attempt &* 0xD6E8_FEB8_6659_FD93)
                attempt += 1
                if let puzzle = build(config: config, minPar: minPar, difficulty: difficulty, random: &random) {
                    return puzzle
                }
            }
            minPar = max(1, minPar - 1)
        }
    }

    private static func build(
        config: Config, minPar: Int, difficulty: Difficulty, random: inout SeededRandom
    ) -> Puzzle? {
        let size = config.size
        var walls: [Wall] = []
        let wallCount = random.int(in: config.walls)
        var guardCount = 0
        while walls.count < wallCount && guardCount < 200 {
            guardCount += 1
            let side: Wall.Side = random.int(below: 2) == 0 ? .right : .bottom
            let x = random.int(below: side == .right ? size - 1 : size)
            let y = random.int(below: side == .bottom ? size - 1 : size)
            let wall = Wall(x: x, y: y, side: side)
            if !walls.contains(wall) { walls.append(wall) }
        }
        let board = Board(width: size, height: size, walls: walls)

        var cells = Array(0..<board.cellCount)
        for i in stride(from: cells.count - 1, to: 0, by: -1) {
            cells.swapAt(i, random.int(below: i + 1))
        }
        let greyCount = random.int(in: config.greys)
        let colorStarts = Array(cells[0..<config.colors])
        let greyStarts = Array(cells[config.colors..<(config.colors + greyCount)])
        let start = colorStarts + greyStarts

        // Explore every position reachable within the par range. The first time
        // a set of coloured-block cells appears, its depth is the true par for
        // using those cells as targets.
        let search = Search(board: board, start: start, colorCount: config.colors)
        var seen: Set<UInt64> = [search.codec.colorKey(start)]
        var candidates: [(par: Int, node: Int, targets: [Int])] = []
        search.run(maxDepth: config.par.upperBound, maxNodes: 400_000) { node, positions, depth in
            let key = search.codec.colorKey(positions)
            guard seen.insert(key).inserted else { return false }
            guard depth >= minPar else { return false }
            // A target hidden under a block at the start would be unreadable.
            for colour in 0..<config.colors where start.contains(positions[colour]) { return false }
            candidates.append((depth, node, Array(positions[0..<config.colors])))
            return false
        }
        guard !candidates.isEmpty else { return nil }

        var pars: [Int] = []
        for candidate in candidates where !pars.contains(candidate.par) { pars.append(candidate.par) }
        let par = pars[random.int(below: pars.count)]
        let matching = candidates.filter { $0.par == par }
        let chosen = matching[random.int(below: matching.count)]

        return Puzzle(
            board: board, colorStarts: colorStarts, targets: chosen.targets, greyStarts: greyStarts,
            difficulty: difficulty, par: par, solution: search.path(to: chosen.node)
        )
    }

    /// FNV-1a. Swift's own hashing is randomised per launch, so it can't be used here.
    static func hash(_ text: String) -> UInt64 {
        var value: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x0000_0100_0000_01B3
        }
        return value
    }
}
