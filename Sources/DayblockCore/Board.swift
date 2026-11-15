/// The four ways the board can be tilted.
public enum Direction: UInt8, CaseIterable, Codable, Sendable {
    case up, right, down, left

    var dx: Int { self == .right ? 1 : (self == .left ? -1 : 0) }
    var dy: Int { self == .down ? 1 : (self == .up ? -1 : 0) }
    var bit: UInt8 { 1 << rawValue }
}

/// A thin wall on one side of a cell. Only the right and bottom sides are stored,
/// so every inner wall has exactly one representation.
public struct Wall: Hashable, Codable, Sendable {
    public enum Side: String, Codable, Sendable { case right, bottom }
    public var x: Int
    public var y: Int
    public var side: Side

    public init(x: Int, y: Int, side: Side) {
        self.x = x
        self.y = y
        self.side = side
    }
}

/// The fixed part of a puzzle: grid size and walls. Cells are numbered
/// row by row from the top-left, so cell = y * width + x.
public struct Board: Hashable, Sendable {
    public let width: Int
    public let height: Int
    public let walls: [Wall]
    /// Per cell, one bit per direction that cannot be moved in (edge or wall).
    let blocked: [UInt8]

    public init(width: Int, height: Int, walls: [Wall] = []) {
        precondition(width > 0 && height > 0 && width * height <= 64, "board must have 1...64 cells")
        self.width = width
        self.height = height
        self.walls = walls
        var blocked = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var mask: UInt8 = 0
                if y == 0 { mask |= Direction.up.bit }
                if y == height - 1 { mask |= Direction.down.bit }
                if x == 0 { mask |= Direction.left.bit }
                if x == width - 1 { mask |= Direction.right.bit }
                blocked[y * width + x] = mask
            }
        }
        for wall in walls {
            precondition(wall.x >= 0 && wall.x < width && wall.y >= 0 && wall.y < height, "wall outside board")
            let cell = wall.y * width + wall.x
            switch wall.side {
            case .right where wall.x < width - 1:
                blocked[cell] |= Direction.right.bit
                blocked[cell + 1] |= Direction.left.bit
            case .bottom where wall.y < height - 1:
                blocked[cell] |= Direction.down.bit
                blocked[cell + width] |= Direction.up.bit
            default:
                break
            }
        }
        self.blocked = blocked
    }

    public var cellCount: Int { width * height }
    public func cell(x: Int, y: Int) -> Int { y * width + x }
    public func x(of cell: Int) -> Int { cell % width }
    public func y(of cell: Int) -> Int { cell / width }

    public func isBlocked(_ cell: Int, _ direction: Direction) -> Bool {
        blocked[cell] & direction.bit != 0
    }

    /// Tilts the board: every block slides in `direction` until it meets an edge,
    /// a wall, or another block. `positions[i]` is the cell of block `i`; the
    /// result uses the same indices.
    public func slide(_ positions: [Int], _ direction: Direction) -> [Int] {
        let count = positions.count
        var order = Array(0..<count)
        // Blocks nearest the side being tilted toward move first.
        func rank(_ index: Int) -> Int {
            let cell = positions[index]
            switch direction {
            case .right: return -x(of: cell)
            case .left: return x(of: cell)
            case .down: return -y(of: cell)
            case .up: return y(of: cell)
            }
        }
        if count > 1 {
            for i in 1..<count {
                let item = order[i]
                let itemRank = rank(item)
                var j = i - 1
                while j >= 0 && rank(order[j]) > itemRank {
                    order[j + 1] = order[j]
                    j -= 1
                }
                order[j + 1] = item
            }
        }
        var occupied: UInt64 = 0
        for cell in positions { occupied |= 1 << UInt64(cell) }
        let step = direction.dx + direction.dy * width
        var result = positions
        for index in order {
            var cell = positions[index]
            occupied &= ~(1 << UInt64(cell))
            while blocked[cell] & direction.bit == 0 {
                let next = cell + step
                if occupied & (1 << UInt64(next)) != 0 { break }
                cell = next
            }
            occupied |= 1 << UInt64(cell)
            result[index] = cell
        }
        return result
    }

    /// Like `slide`, except blocks marked in `fixed` stay where they are and
    /// stop everyone else. An empty or all-false mask is the ordinary tilt.
    public func slide(_ positions: [Int], _ direction: Direction, fixed: [Bool]) -> [Int] {
        if !fixed.contains(true) { return slide(positions, direction) }
        let count = positions.count
        var moving: [Int] = []
        moving.reserveCapacity(count)
        for index in 0..<count where index >= fixed.count || !fixed[index] {
            moving.append(index)
        }
        func rank(_ index: Int) -> Int {
            let cell = positions[index]
            switch direction {
            case .right: return -x(of: cell)
            case .left: return x(of: cell)
            case .down: return -y(of: cell)
            case .up: return y(of: cell)
            }
        }
        if moving.count > 1 {
            for index in 1..<moving.count {
                let item = moving[index]
                let itemRank = rank(item)
                var hole = index - 1
                while hole >= 0 && rank(moving[hole]) > itemRank {
                    moving[hole + 1] = moving[hole]
                    hole -= 1
                }
                moving[hole + 1] = item
            }
        }
        var occupied: UInt64 = 0
        for index in 0..<count where index < fixed.count && fixed[index] {
            occupied |= 1 << UInt64(positions[index])
        }
        let step = direction.dx + direction.dy * width
        var result = positions
        for index in moving {
            var cell = positions[index]
            occupied &= ~(1 << UInt64(cell))
            while blocked[cell] & direction.bit == 0 {
                let next = cell + step
                if occupied & (1 << UInt64(next)) != 0 { break }
                cell = next
            }
            occupied |= 1 << UInt64(cell)
            result[index] = cell
        }
        return result
    }
}

extension Board: Codable {
    private enum CodingKeys: String, CodingKey { case width, height, walls }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            width: try container.decode(Int.self, forKey: .width),
            height: try container.decode(Int.self, forKey: .height),
            walls: try container.decode([Wall].self, forKey: .walls)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(walls, forKey: .walls)
    }
}
