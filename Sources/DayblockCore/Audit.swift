/// Measurements used to judge whether a generated puzzle is trivial, lucky, or
/// actually as hard as its difficulty label. None of this is used during play.
public struct PuzzleProfile: Sendable, Equatable {
    public let par: Int
    /// How many of the four tilt directions the stored shortest solution uses.
    public let directionCount: Int
    /// Some coloured block lands on its own target after a single tilt.
    public let oneSlideHome: Bool
    /// Distinct shortest solutions. Capped; see `solutionsSaturated`.
    public let shortestSolutions: Int
    public let solutionsSaturated: Bool
    /// First tilts that begin at least one shortest solution.
    public let optimalFirstMoves: Int
    /// Positions visited while counting those solutions, up to `par` tilts.
    public let visitedNodes: Int
    public let hasGreys: Bool
    public let hasWalls: Bool
    /// True when this puzzle has grey blocks and deleting them leaves `par` the same.
    public let greysAreDecorative: Bool
    /// True when this puzzle has walls and deleting them leaves `par` the same.
    public let wallsAreDecorative: Bool
    public let luckSolves: Int
    public let luckTrials: Int
    /// Reachable positions, and how many of them can no longer be solved.
    /// Zero unless the puzzle uses the lock rule.
    public let reachableStates: Int
    public let deadEndStates: Int
    public let deadEndsSaturated: Bool
    /// The stored solution's first tilt parks a coloured block.
    public let firstMoveLocks: Bool
    /// Walls, starts, and targets. Equal fingerprints are the same puzzle.
    public let fingerprint: UInt64
    /// The stored solution's tilt sequence.
    public let solutionID: UInt64

    public var luckRate: Double {
        luckTrials == 0 ? 0 : Double(luckSolves) / Double(luckTrials)
    }
}

public enum PuzzleAudit {
    /// Stop counting once a puzzle has this many shortest solutions.
    public static let wayCap = 100_000

    public static func profile(_ puzzle: Puzzle, luckTrials: Int = 16, luckSeed: UInt64 = 1) -> PuzzleProfile {
        let directions = Set(puzzle.solution.map(\.rawValue))
        let solutions = countShortestSolutions(puzzle)
        let greys = greysAreDecorative(puzzle)
        let walls = wallsAreDecorative(puzzle)
        let dead = puzzle.rules.locksOnTarget
            ? deadEnds(puzzle)
            : DeadEndReport(reachable: 0, deadEnds: 0, saturated: false)
        return PuzzleProfile(
            par: puzzle.par,
            directionCount: directions.count,
            oneSlideHome: oneSlideHome(puzzle),
            shortestSolutions: solutions.count,
            solutionsSaturated: solutions.saturated,
            optimalFirstMoves: solutions.firstMoves,
            visitedNodes: solutions.nodes,
            hasGreys: !puzzle.greyStarts.isEmpty,
            hasWalls: !puzzle.board.walls.isEmpty,
            greysAreDecorative: greys,
            wallsAreDecorative: walls,
            luckSolves: luck(puzzle, trials: luckTrials, seed: luckSeed),
            luckTrials: luckTrials,
            reachableStates: dead.reachable,
            deadEndStates: dead.deadEnds,
            deadEndsSaturated: dead.saturated,
            firstMoveLocks: firstMoveLocks(puzzle),
            fingerprint: fingerprint(puzzle),
            solutionID: Generator.hash(puzzle.solution.map { String($0.rawValue) }.joined(separator: ","))
        )
    }

    /// A random player who only makes tilts that move something, for at most twice par.
    static func luck(_ puzzle: Puzzle, trials: Int, seed: UInt64) -> Int {
        guard trials > 0 else { return 0 }
        var random = SeededRandom(seed: seed)
        var solved = 0
        let limit = max(1, puzzle.par * 2)
        for _ in 0..<trials {
            var positions = puzzle.startPositions
            for _ in 0..<limit {
                var options: [Direction] = []
                for direction in Direction.allCases {
                    if puzzle.slide(positions, direction) != positions {
                        options.append(direction)
                    }
                }
                if options.isEmpty { break }
                positions = puzzle.slide(positions, options[random.int(below: options.count)])
                if puzzle.isSolved(positions) {
                    solved += 1
                    break
                }
            }
        }
        return solved
    }

    static func oneSlideHome(_ puzzle: Puzzle) -> Bool {
        let start = puzzle.startPositions
        for direction in Direction.allCases {
            let next = puzzle.slide(start, direction)
            for colour in 0..<puzzle.colorCount {
                if start[colour] != puzzle.targets[colour], next[colour] == puzzle.targets[colour] {
                    return true
                }
            }
        }
        return false
    }

    static func fingerprint(_ puzzle: Puzzle) -> UInt64 {
        let walls = puzzle.board.walls
            .map { "\($0.x),\($0.y),\($0.side.rawValue)" }
            .sorted()
            .joined(separator: ";")
        let colours = puzzle.colorStarts.map(String.init).joined(separator: ",")
        let targets = puzzle.targets.map(String.init).joined(separator: ",")
        let greys = puzzle.greyStarts.sorted().map(String.init).joined(separator: ",")
        return Generator.hash("\(puzzle.board.width)x\(puzzle.board.height)|\(walls)|\(colours)|\(targets)|\(greys)")
    }

    /// Depth of the shortest solve, searching no deeper than `maxDepth`.
    /// Nil means there is no solve that shallow (or the search hit its node cap).
    static func solveDepth(
        board: Board, positions: [Int], targets: [Int], maxDepth: Int, locks: Bool = false
    ) -> Int? {
        let colorCount = targets.count
        func solved(_ positions: [Int]) -> Bool {
            for index in 0..<colorCount where positions[index] != targets[index] { return false }
            return true
        }
        if solved(positions) { return 0 }
        let search = Search(
            board: board, start: positions, colorCount: colorCount, targets: targets, locks: locks
        )
        var found: Int?
        search.run(maxDepth: maxDepth, maxNodes: 250_000) { _, next, depth in
            if solved(next) {
                found = depth
                return true
            }
            return false
        }
        return found
    }

    static func greysAreDecorative(_ puzzle: Puzzle) -> Bool {
        guard !puzzle.greyStarts.isEmpty else { return false }
        let depth = solveDepth(
            board: puzzle.board, positions: puzzle.colorStarts, targets: puzzle.targets,
            maxDepth: puzzle.par, locks: puzzle.rules.locksOnTarget
        )
        return depth == puzzle.par
    }

    static func wallsAreDecorative(_ puzzle: Puzzle) -> Bool {
        guard !puzzle.board.walls.isEmpty else { return false }
        let bare = Board(width: puzzle.board.width, height: puzzle.board.height)
        let depth = solveDepth(
            board: bare, positions: puzzle.startPositions, targets: puzzle.targets,
            maxDepth: puzzle.par, locks: puzzle.rules.locksOnTarget
        )
        return depth == puzzle.par
    }

    private static func countShortestSolutions(_ puzzle: Puzzle) -> (count: Int, saturated: Bool, firstMoves: Int, nodes: Int) {
        let start = puzzle.startPositions
        let codec = StateCodec(colorCount: puzzle.colorCount, blockCount: start.count)
        var keys: [UInt64] = [codec.pack(start)]
        var depth: [Int] = [0]
        var ways: [Int] = [1]
        var firsts: [UInt8] = [0]
        var index: [UInt64: Int] = [keys[0]: 0]
        var solutionWays = 0
        var solutionFirsts: UInt8 = 0
        var saturated = false
        var head = 0
        let nodeCap = 80_000

        while head < keys.count {
            if keys.count >= nodeCap {
                saturated = true
                break
            }
            let here = depth[head]
            if here == puzzle.par {
                let positions = codec.unpack(keys[head])
                if puzzle.isSolved(positions) {
                    solutionWays = cappedAdd(solutionWays, ways[head], saturated: &saturated)
                    solutionFirsts |= firsts[head]
                }
                head += 1
                continue
            }
            let positions = codec.unpack(keys[head])
            for direction in Direction.allCases {
                let next = puzzle.slide(positions, direction)
                if next == positions { continue }
                let key = codec.pack(next)
                let bits: UInt8 = here == 0 ? direction.bit : firsts[head]
                if let existing = index[key] {
                    if depth[existing] == here + 1 {
                        ways[existing] = cappedAdd(ways[existing], ways[head], saturated: &saturated)
                        firsts[existing] |= bits
                    }
                    continue
                }
                index[key] = keys.count
                keys.append(key)
                depth.append(here + 1)
                ways.append(min(ways[head], wayCap))
                firsts.append(bits)
            }
            head += 1
        }

        var firstMoves = 0
        var mask = solutionFirsts
        while mask != 0 {
            if mask & 1 == 1 { firstMoves += 1 }
            mask >>= 1
        }
        return (solutionWays, saturated, firstMoves, keys.count)
    }

    struct DeadEndReport: Sendable {
        var reachable: Int
        var deadEnds: Int
        var saturated: Bool
    }

    /// Positions a player can reach from which no sequence of tilts still solves the puzzle.
    static func deadEnds(_ puzzle: Puzzle, maxNodes: Int = 40_000) -> DeadEndReport {
        let start = puzzle.startPositions
        let codec = StateCodec(colorCount: puzzle.colorCount, blockCount: start.count)
        var keys: [UInt64] = [codec.pack(start)]
        var index: [UInt64: Int] = [keys[0]: 0]
        var reverse: [[Int]] = [[]]
        var solved = [puzzle.isSolved(start)]
        var saturated = false
        var head = 0
        while head < keys.count {
            if keys.count >= maxNodes {
                saturated = true
                break
            }
            let positions = codec.unpack(keys[head])
            for direction in Direction.allCases {
                let next = puzzle.slide(positions, direction)
                if next == positions { continue }
                let key = codec.pack(next)
                let child: Int
                if let existing = index[key] {
                    child = existing
                } else {
                    child = keys.count
                    index[key] = child
                    keys.append(key)
                    reverse.append([])
                    solved.append(puzzle.isSolved(next))
                }
                reverse[child].append(head)
            }
            head += 1
        }
        var live = [Bool](repeating: false, count: keys.count)
        var queue: [Int] = []
        for node in solved.indices where solved[node] {
            live[node] = true
            queue.append(node)
        }
        var cursor = 0
        while cursor < queue.count {
            let node = queue[cursor]
            cursor += 1
            for previous in reverse[node] where !live[previous] {
                live[previous] = true
                queue.append(previous)
            }
        }
        var dead = 0
        for flag in live where !flag { dead += 1 }
        return DeadEndReport(reachable: keys.count, deadEnds: dead, saturated: saturated)
    }

    /// How many first tilts begin a shortest solution. Used while generating.
    static func optimalOpenings(_ puzzle: Puzzle) -> Int {
        guard puzzle.par > 0 else { return 0 }
        let start = puzzle.startPositions
        var openings = 0
        for direction in Direction.allCases {
            let next = puzzle.slide(start, direction)
            if next == start { continue }
            let depth = solveDepth(
                board: puzzle.board, positions: next, targets: puzzle.targets,
                maxDepth: puzzle.par - 1, locks: puzzle.rules.locksOnTarget
            )
            if depth == puzzle.par - 1 { openings += 1 }
        }
        return openings
    }

    private static func firstMoveLocks(_ puzzle: Puzzle) -> Bool {
        guard puzzle.rules.locksOnTarget, let first = puzzle.solution.first else { return false }
        let start = puzzle.startPositions
        let next = puzzle.slide(start, first)
        for colour in 0..<puzzle.colorCount {
            if start[colour] != puzzle.targets[colour], next[colour] == puzzle.targets[colour] {
                return true
            }
        }
        return false
    }

    private static func cappedAdd(_ lhs: Int, _ rhs: Int, saturated: inout Bool) -> Int {
        if lhs >= wayCap || rhs >= wayCap || lhs > wayCap - rhs {
            saturated = true
            return wayCap
        }
        return lhs + rhs
    }
}
