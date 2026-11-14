/// Packs block positions into one integer so states can be compared quickly.
/// Grey blocks are interchangeable, so they are sorted before packing.
struct StateCodec {
    let colorCount: Int
    let blockCount: Int

    init(colorCount: Int, blockCount: Int) {
        precondition(blockCount <= 10, "at most 10 blocks")
        self.colorCount = colorCount
        self.blockCount = blockCount
    }

    func pack(_ positions: [Int]) -> UInt64 {
        var key: UInt64 = 0
        for i in 0..<colorCount { key = key << 6 | UInt64(positions[i]) }
        if blockCount > colorCount {
            let greys = positions[colorCount...].sorted()
            for cell in greys { key = key << 6 | UInt64(cell) }
        }
        return key
    }

    func unpack(_ key: UInt64) -> [Int] {
        var positions = [Int](repeating: 0, count: blockCount)
        var key = key
        for i in stride(from: blockCount - 1, through: 0, by: -1) {
            positions[i] = Int(key & 63)
            key >>= 6
        }
        return positions
    }

    func colorKey(_ positions: [Int]) -> UInt64 {
        var key: UInt64 = 0
        for i in 0..<colorCount { key = key << 6 | UInt64(positions[i]) }
        return key
    }
}

/// Breadth-first search over every position reachable by tilting.
/// Because it explores one swipe deeper at a time, the first time a
/// position is seen is always by a shortest route.
final class Search {
    let board: Board
    let codec: StateCodec
    private(set) var keys: [UInt64] = []
    private var parents: [Int32] = []
    private var moves: [UInt8] = []
    private var depths: [UInt16] = []
    private var index: [UInt64: Int32] = [:]

    init(board: Board, start: [Int], colorCount: Int) {
        self.board = board
        self.codec = StateCodec(colorCount: colorCount, blockCount: start.count)
        let key = codec.pack(start)
        keys.append(key)
        parents.append(-1)
        moves.append(0)
        depths.append(0)
        index[key] = 0
    }

    /// Explores until nothing new is left, `maxDepth` swipes are reached, or
    /// `maxNodes` positions have been seen. `onNew` is called once per newly
    /// found position with (node, positions, depth); return true to stop.
    func run(maxDepth: Int, maxNodes: Int, onNew: (Int, [Int], Int) -> Bool) {
        var head = 0
        while head < keys.count {
            let depth = Int(depths[head])
            if depth >= maxDepth { return }
            let positions = codec.unpack(keys[head])
            for direction in Direction.allCases {
                let next = board.slide(positions, direction)
                if next == positions { continue }
                let key = codec.pack(next)
                if index[key] != nil { continue }
                let node = keys.count
                keys.append(key)
                parents.append(Int32(head))
                moves.append(direction.rawValue)
                depths.append(UInt16(depth + 1))
                index[key] = Int32(node)
                if onNew(node, next, depth + 1) { return }
                if keys.count >= maxNodes { return }
            }
            head += 1
        }
    }

    func path(to node: Int) -> [Direction] {
        var path: [Direction] = []
        var current = node
        while parents[current] >= 0 {
            path.append(Direction(rawValue: moves[current])!)
            current = Int(parents[current])
        }
        return path.reversed()
    }
}

public enum Solver {
    public struct Solution: Equatable, Sendable {
        public let moves: [Direction]
        public var count: Int { moves.count }
    }

    /// Finds a shortest solution from `positions`, or nil when there is none
    /// (or none within `maxNodes` explored positions).
    public static func solve(
        board: Board, positions: [Int], targets: [Int], maxNodes: Int = 3_000_000
    ) -> Solution? {
        let colorCount = targets.count
        func solved(_ p: [Int]) -> Bool {
            for i in 0..<colorCount where p[i] != targets[i] { return false }
            return true
        }
        if solved(positions) { return Solution(moves: []) }
        let search = Search(board: board, start: positions, colorCount: colorCount)
        var goal: Int?
        search.run(maxDepth: .max, maxNodes: maxNodes) { node, p, _ in
            if solved(p) {
                goal = node
                return true
            }
            return false
        }
        return goal.map { Solution(moves: search.path(to: $0)) }
    }

    public static func solve(_ puzzle: Puzzle, from positions: [Int]? = nil) -> Solution? {
        solve(board: puzzle.board, positions: positions ?? puzzle.startPositions, targets: puzzle.targets)
    }
}
