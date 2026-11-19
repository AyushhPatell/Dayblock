/// Makes Fit puzzles. Same seed, same puzzle, on every device.
public enum FitGenerator {
    /// Changing the generator changes every Fit daily. Bump only before launch.
    public static let version = 1

    struct Config {
        let width: Int
        let height: Int
        /// How many cells the outline has.
        let cells: ClosedRange<Int>
        /// Piece sizes, in cells.
        let sizes: ClosedRange<Int>
        let rotates: Bool
        /// Clues are added until at most this many complete fills exist.
        let maxSolutions: Int
        /// Clues added after that, as help.
        let extraClues: Int
        /// Never more clues than this.
        let maxClues: Int
        let difficulty: Difficulty
    }

    static func config(for weekday: PuzzleDate.Weekday) -> Config {
        switch weekday {
        case .monday:
            return Config(width: 6, height: 5, cells: 12...14, sizes: 3...4, rotates: false, maxSolutions: 4, extraClues: 1, maxClues: 4, difficulty: .easy)
        case .tuesday:
            return Config(width: 6, height: 6, cells: 15...18, sizes: 3...4, rotates: false, maxSolutions: 2, extraClues: 1, maxClues: 5, difficulty: .easy)
        case .wednesday:
            return Config(width: 6, height: 6, cells: 16...20, sizes: 3...5, rotates: true, maxSolutions: 2, extraClues: 1, maxClues: 6, difficulty: .medium)
        case .thursday:
            return Config(width: 7, height: 6, cells: 20...24, sizes: 3...5, rotates: true, maxSolutions: 1, extraClues: 1, maxClues: 7, difficulty: .medium)
        case .friday:
            return Config(width: 7, height: 7, cells: 23...28, sizes: 4...5, rotates: true, maxSolutions: 1, extraClues: 0, maxClues: 8, difficulty: .hard)
        case .saturday:
            return Config(width: 7, height: 7, cells: 26...31, sizes: 4...5, rotates: true, maxSolutions: 1, extraClues: 0, maxClues: 8, difficulty: .hard)
        case .sunday:
            return Config(width: 8, height: 7, cells: 30...36, sizes: 4...5, rotates: true, maxSolutions: 1, extraClues: 0, maxClues: 9, difficulty: .expert)
        }
    }

    /// Levels start with a few small pieces and no turning, and grow slowly.
    static func levelConfig(_ level: Int) -> Config {
        switch level {
        case ..<4:
            return Config(width: 4, height: 4, cells: 6...8, sizes: 2...3, rotates: false, maxSolutions: 10, extraClues: 1, maxClues: 3, difficulty: .easy)
        case 4..<11:
            return Config(width: 5, height: 5, cells: 9...12, sizes: 3...4, rotates: false, maxSolutions: 6, extraClues: 1, maxClues: 4, difficulty: .easy)
        case 11..<21:
            return Config(width: 6, height: 5, cells: 12...16, sizes: 3...4, rotates: false, maxSolutions: 3, extraClues: 1, maxClues: 5, difficulty: .easy)
        case 21..<36:
            return Config(width: 6, height: 6, cells: 15...19, sizes: 3...5, rotates: true, maxSolutions: 3, extraClues: 1, maxClues: 6, difficulty: .medium)
        case 36..<61:
            return Config(width: 7, height: 6, cells: 19...25, sizes: 3...5, rotates: true, maxSolutions: 2, extraClues: 0, maxClues: 7, difficulty: .medium)
        case 61..<101:
            return Config(width: 7, height: 7, cells: 24...30, sizes: 4...5, rotates: true, maxSolutions: 1, extraClues: 0, maxClues: 8, difficulty: .hard)
        default:
            return Config(width: 8, height: 7, cells: 28...36, sizes: 4...5, rotates: true, maxSolutions: 1, extraClues: 0, maxClues: 9, difficulty: .expert)
        }
    }

    public static func difficulty(for weekday: PuzzleDate.Weekday) -> Difficulty { config(for: weekday).difficulty }

    public static func daily(for date: PuzzleDate) -> FitPuzzle {
        generate(seed: Generator.hash("dayblock-fit-v\(version)-\(date.iso)"), config: config(for: date.weekday))
    }

    /// Level `n` (from 1) is the same puzzle for everyone.
    public static func level(_ number: Int) -> FitPuzzle {
        generate(seed: Generator.hash("dayblock-fit-level-v\(version)-\(max(1, number))"), config: levelConfig(max(1, number)))
    }

    static func generate(seed: UInt64, config: Config) -> FitPuzzle {
        for attempt in 0..<600 as Range<UInt64> {
            var random = SeededRandom(seed: seed &+ attempt &* 0xD6E8_FEB8_6659_FD93)
            guard let (width, height, outline) = silhouette(config: config, random: &random) else { continue }
            for _ in 0..<12 {
                guard let parts = partition(width: width, height: height, outline: outline, config: config, random: &random),
                      let puzzle = finish(width: width, height: height, outline: outline, parts: parts,
                                          config: config, random: &random)
                else { continue }
                return puzzle
            }
        }
        return simplest
    }

    /// A tiny always-valid puzzle, used only if every attempt somehow failed.
    static let simplest = FitPuzzle(
        width: 3, height: 2, outline: Array(repeating: true, count: 6),
        pieces: [FitPiece(cells: [FitCell(x: 0, y: 0), FitCell(x: 1, y: 0), FitCell(x: 2, y: 0)]),
                 FitPiece(cells: [FitCell(x: 0, y: 0), FitCell(x: 1, y: 0), FitCell(x: 2, y: 0)])],
        clues: [], rotates: false, trayRotations: [0, 0],
        solution: [FitPlacement(rotation: 0, x: 0, y: 0), FitPlacement(rotation: 0, x: 0, y: 1)], difficulty: .easy
    )

    // MARK: Outline

    /// Grows a mirror-symmetric shape, fills any holes, and crops it to its bounds.
    static func silhouette(config: Config, random: inout SeededRandom) -> (Int, Int, [Bool])? {
        let width = config.width
        let height = config.height
        var inside = [Bool](repeating: false, count: width * height)
        func mirror(_ cell: Int) -> Int { (cell / width) * width + (width - 1 - cell % width) }
        func neighbours(_ cell: Int) -> [Int] {
            let x = cell % width, y = cell / width
            var result: [Int] = []
            if x > 0 { result.append(cell - 1) }
            if x < width - 1 { result.append(cell + 1) }
            if y > 0 { result.append(cell - width) }
            if y < height - 1 { result.append(cell + width) }
            return result
        }
        let seed = (height / 2) * width + width / 2
        inside[seed] = true
        inside[mirror(seed)] = true
        let target = random.int(in: config.cells)
        var count = inside.filter { $0 }.count
        var guardCount = 0
        while count < target && guardCount < 400 {
            guardCount += 1
            // Frontier cells, weighted towards ones that touch the shape on
            // several sides, so the outline stays smooth rather than spiky.
            var frontier: [(cell: Int, weight: Int)] = []
            for cell in inside.indices where !inside[cell] {
                let touching = neighbours(cell).filter { inside[$0] }.count
                if touching > 0 { frontier.append((cell, touching * touching)) }
            }
            let total = frontier.reduce(0) { $0 + $1.weight }
            guard total > 0 else { break }
            var pick = random.int(below: total)
            var chosen = frontier[0].cell
            for entry in frontier {
                if pick < entry.weight { chosen = entry.cell; break }
                pick -= entry.weight
            }
            let mirrored = mirror(chosen)
            // Adding a cell and its mirror can overshoot by one; stop rather than go over.
            let adds = chosen == mirrored ? 1 : 2
            if count + adds > config.cells.upperBound { break }
            inside[chosen] = true
            inside[mirrored] = true
            count += adds
        }
        // Fill holes: anything not reachable from the border through empty cells.
        var outside = [Bool](repeating: false, count: width * height)
        var queue = inside.indices.filter { cell in
            !inside[cell] && (cell % width == 0 || cell % width == width - 1 || cell / width == 0 || cell / width == height - 1)
        }
        for cell in queue { outside[cell] = true }
        while let cell = queue.popLast() {
            for next in neighbours(cell) where !inside[next] && !outside[next] {
                outside[next] = true
                queue.append(next)
            }
        }
        for cell in inside.indices where !inside[cell] && !outside[cell] { inside[cell] = true }
        count = inside.filter { $0 }.count
        guard config.cells.contains(count) else { return nil }

        // Crop to the shape's bounds.
        var minX = width, maxX = -1, minY = height, maxY = -1
        for cell in inside.indices where inside[cell] {
            minX = min(minX, cell % width); maxX = max(maxX, cell % width)
            minY = min(minY, cell / width); maxY = max(maxY, cell / width)
        }
        var cropped: [Bool] = []
        for y in minY...maxY { for x in minX...maxX { cropped.append(inside[y * width + x]) } }
        return (maxX - minX + 1, maxY - minY + 1, cropped)
    }

    // MARK: Pieces

    /// Cuts the outline into pieces. Always starts from the most hemmed-in
    /// empty cell, so no lone cell gets stranded.
    static func partition(width: Int, height: Int, outline: [Bool], config: Config,
                          random: inout SeededRandom) -> [[Int]]? {
        var owner = [Int](repeating: -1, count: width * height)
        var parts: [[Int]] = []
        func neighbours(_ cell: Int) -> [Int] {
            let x = cell % width, y = cell / width
            var result: [Int] = []
            if x > 0 { result.append(cell - 1) }
            if x < width - 1 { result.append(cell + 1) }
            if y > 0 { result.append(cell - width) }
            if y < height - 1 { result.append(cell + width) }
            return result.filter { outline[$0] }
        }
        func free(_ cell: Int) -> Bool { outline[cell] && owner[cell] < 0 }
        func freeNeighbours(_ cell: Int) -> Int { neighbours(cell).filter(free).count }

        var remaining = outline.filter { $0 }.count
        while remaining > 0 {
            let open = owner.indices.filter(free)
            let fewest = open.map(freeNeighbours).min()!
            let tight = open.filter { freeNeighbours($0) == fewest }
            let start = tight[random.int(below: tight.count)]
            var size = random.int(in: config.sizes)
            size = min(size, remaining)
            // Don't leave a remainder too small to make a piece.
            if remaining - size > 0 && remaining - size < config.sizes.lowerBound {
                size = remaining - config.sizes.lowerBound >= config.sizes.lowerBound
                    ? remaining - config.sizes.lowerBound : remaining
            }
            guard size <= config.sizes.upperBound else { return nil }
            var piece = [start]
            owner[start] = parts.count
            while piece.count < size {
                var candidates: [Int] = []
                for cell in piece { for next in neighbours(cell) where free(next) && !candidates.contains(next) { candidates.append(next) } }
                guard !candidates.isEmpty else { break }
                let least = candidates.map(freeNeighbours).min()!
                let best = candidates.filter { freeNeighbours($0) == least }
                let next = best[random.int(below: best.count)]
                owner[next] = parts.count
                piece.append(next)
            }
            guard config.sizes.contains(piece.count) else { return nil }
            parts.append(piece)
            remaining -= piece.count
            // Every leftover region must still be big enough for a piece.
            var seen = Set<Int>()
            for cell in owner.indices where free(cell) && !seen.contains(cell) {
                var region = [cell]
                seen.insert(cell)
                var index = 0
                while index < region.count {
                    for next in neighbours(region[index]) where free(next) && seen.insert(next).inserted { region.append(next) }
                    index += 1
                }
                if region.count < config.sizes.lowerBound { return nil }
            }
        }
        return parts
    }

    /// Turns cut pieces into a puzzle: rejects look-alike pieces, then adds
    /// number clues until the answer is (nearly) unique.
    static func finish(width: Int, height: Int, outline: [Bool], parts: [[Int]], config: Config,
                       random: inout SeededRandom) -> FitPuzzle? {
        var pieces: [FitPiece] = []
        var solution: [FitPlacement] = []
        for part in parts {
            let cells = part.map { FitCell(x: $0 % width, y: $0 / width) }
            let piece = FitPiece(cells: cells)
            pieces.append(piece)
            solution.append(FitPlacement(rotation: 0, x: cells.map(\.x).min()!, y: cells.map(\.y).min()!))
        }
        // Two pieces that look the same make the tray confusing and the count of answers misleading.
        let shapes = pieces.map { $0.canonical(rotating: config.rotates) }
        guard Set(shapes.map { $0.map { "\($0.x),\($0.y)" }.joined(separator: ";") }).count == pieces.count else { return nil }

        let trayRotations = pieces.indices.map { index -> Int in
            guard config.rotates else { return 0 }
            let turns = pieces[index].distinctRotations
            return turns[random.int(below: turns.count)]
        }
        // Shuffle the tray, so the order gives nothing away.
        var order = Array(pieces.indices)
        for i in stride(from: order.count - 1, to: 0, by: -1) { order.swapAt(i, random.int(below: i + 1)) }
        pieces = order.map { pieces[$0] }
        solution = order.map { solution[$0] }
        let tray = order.map { trayRotations[$0] }
        let partsInOrder = order.map { parts[$0] }

        var clues: [FitClue] = []
        func make() -> FitPuzzle {
            FitPuzzle(width: width, height: height, outline: outline, pieces: pieces, clues: clues.sorted { $0.cell < $1.cell },
                      rotates: config.rotates, trayRotations: tray, solution: solution, difficulty: config.difficulty)
        }
        // Candidate clue cells, one pass per piece first so clues spread out.
        var candidates: [Int] = []
        var pools = partsInOrder.map { part -> [Int] in
            var cells = part
            for i in stride(from: cells.count - 1, to: 0, by: -1) { cells.swapAt(i, random.int(below: i + 1)) }
            return cells
        }
        var pieceOrder = Array(pools.indices)
        for i in stride(from: pieceOrder.count - 1, to: 0, by: -1) { pieceOrder.swapAt(i, random.int(below: i + 1)) }
        var added = true
        while added {
            added = false
            for index in pieceOrder where !pools[index].isEmpty {
                candidates.append(pools[index].removeLast())
                added = true
            }
        }
        func sizeOfPiece(covering cell: Int) -> Int { partsInOrder.first { $0.contains(cell) }!.count }

        // Count with headroom, so a clue that halves 40 answers isn't mistaken
        // for one that does nothing.
        let measure = max(60, config.maxSolutions + 1)
        var solutions = FitSolver.countSolutions(make(), limit: measure)
        var next = 0
        while solutions > config.maxSolutions {
            guard clues.count < config.maxClues, next < candidates.count else { return nil }
            let cell = candidates[next]
            next += 1
            let clue = FitClue(cell: cell, size: sizeOfPiece(covering: cell))
            clues.append(clue)
            let reduced = FitSolver.countSolutions(make(), limit: measure)
            // A clue that changes nothing is noise; take it back.
            if reduced >= solutions {
                clues.removeLast()
                continue
            }
            solutions = reduced
        }
        var extras = config.extraClues
        while extras > 0 && next < candidates.count && clues.count < config.maxClues {
            clues.append(FitClue(cell: candidates[next], size: sizeOfPiece(covering: candidates[next])))
            next += 1
            extras -= 1
        }
        return make()
    }
}
