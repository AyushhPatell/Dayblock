/// Makes Paint puzzles. Same seed, same puzzle, on every device.
public enum PaintGenerator {
    /// Changing the generator changes every Paint daily. Bump only before launch.
    public static let version = 2

    struct Config {
        let width: Int
        let height: Int
        /// How many corridor runs to carve.
        let steps: ClosedRange<Int>
        let par: ClosedRange<Int>
        let floor: ClosedRange<Int>
        /// Chance (in percent) that a run ends on a sticky pad.
        let padChance: Int
        /// Random swiping must average at least this multiple of par (in percent),
        /// so planning a route actually beats wandering. 0 turns the check off.
        let wander: Int
        /// Reject boards where random play averages above this multiple of par (percent). 0 = off.
        let maxWander: Int
        /// Reject boards where fewer than this percent of solution swipes paint something new. 0 = off.
        let minUseful: Int
        let difficulty: Difficulty
    }

    static func config(for weekday: PuzzleDate.Weekday) -> Config {
        switch weekday {
        case .monday:
            // Shorter corridors + wander ceiling; floor min stays 10 so boards aren't tiny.
            return Config(width: 5, height: 5, steps: 3...5, par: 4...6, floor: 10...16, padChance: 0, wander: 110, maxWander: 240, minUseful: 85, difficulty: .easy)
        case .tuesday:
            return Config(width: 6, height: 6, steps: 5...7, par: 5...7, floor: 13...20, padChance: 0, wander: 120, maxWander: 280, minUseful: 85, difficulty: .easy)
        case .wednesday:
            return Config(width: 6, height: 6, steps: 8...11, par: 6...8, floor: 16...28, padChance: 20, wander: 150, maxWander: 0, minUseful: 0, difficulty: .medium)
        case .thursday:
            return Config(width: 6, height: 6, steps: 9...12, par: 7...9, floor: 17...30, padChance: 20, wander: 150, maxWander: 0, minUseful: 0, difficulty: .medium)
        case .friday:
            return Config(width: 7, height: 7, steps: 10...13, par: 8...11, floor: 22...36, padChance: 25, wander: 160, maxWander: 0, minUseful: 0, difficulty: .hard)
        case .saturday:
            return Config(width: 7, height: 7, steps: 11...14, par: 9...12, floor: 24...38, padChance: 25, wander: 160, maxWander: 0, minUseful: 0, difficulty: .hard)
        case .sunday:
            return Config(width: 7, height: 7, steps: 12...16, par: 10...14, floor: 26...40, padChance: 30, wander: 170, maxWander: 0, minUseful: 0, difficulty: .expert)
        }
    }

    /// Levels start tiny and grow slowly, so the first ten minutes are easy.
    static func levelConfig(_ level: Int) -> Config {
        switch level {
        case ..<4:
            return Config(width: 4, height: 4, steps: 3...4, par: 2...3, floor: 5...10, padChance: 0, wander: 0, maxWander: 0, minUseful: 0, difficulty: .easy)
        case 4..<11:
            return Config(width: 5, height: 5, steps: 3...5, par: 3...5, floor: 8...14, padChance: 0, wander: 100, maxWander: 240, minUseful: 85, difficulty: .easy)
        case 11..<21:
            return Config(width: 5, height: 5, steps: 5...7, par: 4...6, floor: 10...18, padChance: 0, wander: 130, maxWander: 0, minUseful: 0, difficulty: .easy)
        case 21..<36:
            return Config(width: 6, height: 6, steps: 7...10, par: 5...7, floor: 14...26, padChance: 15, wander: 140, maxWander: 0, minUseful: 0, difficulty: .medium)
        case 36..<61:
            return Config(width: 6, height: 6, steps: 8...12, par: 6...9, floor: 16...30, padChance: 20, wander: 150, maxWander: 0, minUseful: 0, difficulty: .medium)
        case 61..<101:
            return Config(width: 7, height: 7, steps: 10...13, par: 7...11, floor: 20...36, padChance: 25, wander: 160, maxWander: 0, minUseful: 0, difficulty: .hard)
        default:
            return Config(width: 7, height: 7, steps: 11...16, par: 9...13, floor: 24...40, padChance: 30, wander: 160, maxWander: 0, minUseful: 0, difficulty: .expert)
        }
    }

    public static func difficulty(for weekday: PuzzleDate.Weekday) -> Difficulty { config(for: weekday).difficulty }

    public static func daily(for date: PuzzleDate) -> PaintPuzzle {
        generate(seed: Generator.hash("dayblock-paint-v\(version)-\(date.iso)"), config: config(for: date.weekday))
    }

    /// Level `n` (from 1) is the same puzzle for everyone.
    public static func level(_ number: Int) -> PaintPuzzle {
        generate(seed: Generator.hash("dayblock-paint-level-v\(version)-\(max(1, number))"), config: levelConfig(max(1, number)))
    }

    static func generate(seed: UInt64, config: Config) -> PaintPuzzle {
        var fallback: PaintPuzzle?
        var fallbackDistance = Int.max
        for attempt in 0..<3000 as Range<UInt64> {
            var random = SeededRandom(seed: seed &+ attempt &* 0xD6E8_FEB8_6659_FD93)
            guard let (board, start) = carve(config: config, random: &random),
                  config.floor.contains(board.floorCount),
                  PaintSolver.isAlwaysFinishable(board, start: start),
                  let solution = PaintSolver.solve(board, from: start, painted: 1 << UInt64(start), maxNodes: 250_000),
                  !solution.isEmpty
            else { continue }
            let par = solution.count
            let puzzle = PaintPuzzle(board: board, start: start, difficulty: config.difficulty, par: par, solution: solution)
            // Remember the closest miss, so a stubborn seed still yields a fair puzzle.
            let distance = par < config.par.lowerBound ? config.par.lowerBound - par
                : par > config.par.upperBound ? par - config.par.upperBound : 0
            if distance < fallbackDistance {
                fallback = puzzle
                fallbackDistance = distance
            }
            guard distance == 0 else { continue }
            // A route that only ever uses two directions is a zig-zag, not a puzzle.
            if par >= 4 && Set(solution).count < 3 { continue }
            let ratio = wanderRatio(puzzle, seed: seed &+ attempt)
            if config.wander > 0 && ratio < config.wander { continue }
            if config.maxWander > 0 && ratio > config.maxWander { continue }
            if config.minUseful > 0 && usefulSwipePercent(puzzle) < config.minUseful { continue }
            return puzzle
        }
        return fallback ?? simplest
    }

    /// A tiny always-valid puzzle, used only if every attempt somehow failed.
    static let simplest: PaintPuzzle = {
        let board = PaintBoard(width: 3, height: 3, open: [true, true, true, false, false, true, false, false, true],
                               pads: Array(repeating: false, count: 9))
        return PaintPuzzle(board: board, start: 0, difficulty: .easy, par: 2, solution: [.right, .down])
    }()

    /// Carves corridors into a solid grid. Each run ends where the block will
    /// really stop: at the edge, against a cell kept solid, or on a pad.
    static func carve(config: Config, random: inout SeededRandom) -> (PaintBoard, Int)? {
        let width = config.width
        let height = config.height
        let count = width * height
        var open = [Bool](repeating: false, count: count)
        var keepSolid = [Bool](repeating: false, count: count)
        var pads = [Bool](repeating: false, count: count)
        let start = random.int(below: count)
        open[start] = true
        var position = start
        let steps = random.int(in: config.steps)
        var done = 0
        var tries = 0
        while done < steps && tries < steps * 14 {
            tries += 1
            let direction = Direction(rawValue: UInt8(random.int(below: 4)))!
            var line: [Int] = []
            var at = position
            while let next = PaintBoard.neighbour(of: at, direction, width: width, height: height) {
                line.append(next)
                at = next
            }
            guard !line.isEmpty else { continue }
            let length = random.int(in: 1...line.count)
            let path = Array(line[0..<length])
            if path.contains(where: { keepSolid[$0] }) { continue }
            // A pad part-way along would stop the block early.
            if path.dropLast().contains(where: { pads[$0] }) { continue }
            let end = path[path.count - 1]
            var endsOnPad = false
            if length < line.count {
                let beyond = line[length]
                if open[beyond] {
                    // The block would roll on into floor already carved; only a pad stops it here.
                    guard random.int(below: 100) < config.padChance else { continue }
                    endsOnPad = true
                } else if random.int(below: 100) < config.padChance / 2 {
                    endsOnPad = true
                } else {
                    keepSolid[beyond] = true
                }
            }
            for cell in path { open[cell] = true }
            if endsOnPad { pads[end] = true }
            position = end
            done += 1
        }
        guard done >= config.steps.lowerBound else { return nil }
        return crop(width: width, height: height, open: open, pads: pads, start: start)
    }

    /// Trims solid rows and columns from the edges, so the board on screen is
    /// only as big as the floor.
    static func crop(width: Int, height: Int, open: [Bool], pads: [Bool], start: Int) -> (PaintBoard, Int) {
        var minX = width, maxX = -1, minY = height, maxY = -1
        for cell in open.indices where open[cell] {
            minX = min(minX, cell % width); maxX = max(maxX, cell % width)
            minY = min(minY, cell / width); maxY = max(maxY, cell / width)
        }
        let newWidth = maxX - minX + 1
        let newHeight = maxY - minY + 1
        var newOpen: [Bool] = []
        var newPads: [Bool] = []
        for y in minY...maxY {
            for x in minX...maxX {
                newOpen.append(open[y * width + x])
                newPads.append(pads[y * width + x])
            }
        }
        let newStart = (start / width - minY) * newWidth + (start % width - minX)
        return (PaintBoard(width: newWidth, height: newHeight, open: newOpen, pads: newPads), newStart)
    }

    /// How many swipes, as a percentage of par, a player swiping at random needs
    /// on average. Paint can never get stuck, so random play always finishes.
    public static func wanderRatio(_ puzzle: PaintPuzzle, seed: UInt64, runs: Int = 6) -> Int {
        var random = SeededRandom(seed: seed ^ 0x5EED_5EED)
        var total = 0
        let cap = puzzle.par * 8
        for _ in 0..<runs {
            var position = puzzle.start
            var painted = puzzle.startMask
            var swipes = 0
            while painted != puzzle.board.floorMask && swipes < cap {
                let options = Direction.allCases.filter { puzzle.board.move(from: position, $0).to != position }
                let move = puzzle.board.move(from: position, options[random.int(below: options.count)])
                position = move.to
                painted |= move.painted
                swipes += 1
            }
            total += swipes
        }
        return total * 100 / (runs * puzzle.par)
    }

    /// Share of solution swipes that paint at least one new cell (percent).
    static func usefulSwipePercent(_ puzzle: PaintPuzzle) -> Int {
        var position = puzzle.start
        var painted = puzzle.startMask
        var useful = 0
        for dir in puzzle.solution {
            let move = puzzle.board.move(from: position, dir)
            if (move.painted & ~painted) != 0 { useful += 1 }
            position = move.to
            painted |= move.painted
        }
        guard !puzzle.solution.isEmpty else { return 100 }
        return useful * 100 / puzzle.solution.count
    }
}
