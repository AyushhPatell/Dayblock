import Foundation
import DayblockCore

// Usage:
//   dayblock-cli sample [days] [yyyy-mm-dd]   print daily puzzles
//   dayblock-cli stats [count]                par spread and speed per difficulty
//   dayblock-cli audit [days] [practiceEach] [yyyy-mm-dd]
//       quality numbers for a run of dailies and practice puzzles
//   dayblock-cli audit-lock [practiceEach]
//       the same measurements for lock-rule practice puzzles

func parseDate(_ text: String) -> PuzzleDate? { PuzzleDate(iso: text) }

func arrows(_ moves: [Direction]) -> String {
    moves.map { ["↑", "→", "↓", "←"][Int($0.rawValue)] }.joined(separator: " ")
}

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "sample"

switch command {
case "sample":
    let days = arguments.count > 1 ? Int(arguments[1]) ?? 7 : 7
    var date = arguments.count > 2 ? parseDate(arguments[2]) ?? PuzzleDate(year: 2026, month: 11, day: 16)
                                   : PuzzleDate(year: 2026, month: 11, day: 16)
    for _ in 0..<days {
        let puzzle = Generator.daily(for: date)
        print("\(date.iso)  \(date.weekday)  \(puzzle.difficulty.rawValue)  best: \(puzzle.par)")
        print(puzzle.render())
        print("solution: \(arrows(puzzle.solution))\n")
        date = date.adding(days: 1)
    }
case "stats":
    let count = arguments.count > 1 ? Int(arguments[1]) ?? 50 : 50
    for difficulty in Difficulty.allCases {
        var spread: [Int: Int] = [:]
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for seed in 0..<count {
                let puzzle = Generator.practice(seed: UInt64(seed), difficulty: difficulty)
                spread[puzzle.par, default: 0] += 1
            }
        }
        let summary = spread.keys.sorted().map { "\($0):\(spread[$0]!)" }.joined(separator: " ")
        let perPuzzle = elapsed / count
        print("\(difficulty.rawValue)  par spread [\(summary)]  \(perPuzzle) per puzzle")
    }
case "play":
    guard arguments.count > 2, let date = parseDate(arguments[1]) else {
        print("usage: dayblock-cli play yyyy-mm-dd right,right,down")
        break
    }
    let names: [String: Direction] = ["up": .up, "right": .right, "down": .down, "left": .left]
    let moves = arguments[2].split(separator: ",").compactMap { names[String($0)] }
    var session = GameSession(puzzle: Generator.daily(for: date))
    for move in moves { session.swipe(move) }
    let positions = session.positions.map(String.init).joined(separator: ",")
    print("swipes=\(session.swipeCount) solved=\(session.isSolved) positions=\(positions)")
case "audit":
    let days = arguments.count > 1 ? Int(arguments[1]) ?? 365 : 365
    let practiceEach = arguments.count > 2 ? Int(arguments[2]) ?? 500 : 500
    let start = arguments.count > 3 ? parseDate(arguments[3]) ?? PuzzleDate(year: 2026, month: 11, day: 14)
                                    : PuzzleDate(year: 2026, month: 11, day: 14)
    runAudit(days: days, practiceEach: practiceEach, start: start)
case "audit-lock":
    let practiceEach = arguments.count > 1 ? Int(arguments[1]) ?? 200 : 200
    runLockAudit(practiceEach: practiceEach)
case "pins":
    for iso in ["2026-11-14", "2026-11-20"] {
        let date = parseDate(iso)!
        let puzzle = Generator.daily(for: date)
        let moves = puzzle.solution.map { String($0.rawValue) }.joined(separator: ",")
        print("\(iso) par=\(puzzle.par) starts=\(puzzle.colorStarts) targets=\(puzzle.targets) greys=\(puzzle.greyStarts) moves=\(moves)")
    }
default:
    print("unknown command \(command)")
}

struct AuditBucket {
    var count = 0
    var pars: [Int: Int] = [:]
    var nodes: [Int] = []
    var firstMoves: [Int] = []
    var solutions: [Int] = []
    var luckSolves = 0
    var luckTrials = 0
    var twoDirections = 0
    var oneSlide = 0
    var withGreys = 0
    var decorativeGreys = 0
    var withWalls = 0
    var decorativeWalls = 0
    var saturated = 0
    var fingerprints: [UInt64: Int] = [:]
    var shapes: [UInt64: Int] = [:]

    mutating func add(_ profile: PuzzleProfile, shape: UInt64) {
        count += 1
        pars[profile.par, default: 0] += 1
        nodes.append(profile.visitedNodes)
        firstMoves.append(profile.optimalFirstMoves)
        solutions.append(profile.shortestSolutions)
        luckSolves += profile.luckSolves
        luckTrials += profile.luckTrials
        if profile.directionCount <= 2 { twoDirections += 1 }
        if profile.oneSlideHome { oneSlide += 1 }
        if profile.hasGreys {
            withGreys += 1
            if profile.greysAreDecorative { decorativeGreys += 1 }
        }
        if profile.hasWalls {
            withWalls += 1
            if profile.wallsAreDecorative { decorativeWalls += 1 }
        }
        if profile.solutionsSaturated { saturated += 1 }
        fingerprints[profile.fingerprint, default: 0] += 1
        shapes[shape, default: 0] += 1
    }
}

func median(_ values: [Int]) -> Int {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}

func parList(_ pars: [Int: Int]) -> [Int] {
    var values: [Int] = []
    for (par, count) in pars {
        values.append(contentsOf: repeatElement(par, count: count))
    }
    return values
}

func percent(_ part: Int, _ whole: Int) -> String {
    guard whole > 0 else { return "n/a" }
    return String(format: "%.0f%%", 100 * Double(part) / Double(whole))
}

func runAudit(days: Int, practiceEach: Int, start: PuzzleDate) {
    let trials = 12
    var byWeekday: [PuzzleDate.Weekday: AuditBucket] = [:]
    var dailyFingerprints: [UInt64: Int] = [:]
    var dailyShapes: [String: Int] = [:]
    var date = start
    for index in 0..<days {
        let puzzle = Generator.daily(for: date)
        let profile = PuzzleAudit.profile(puzzle, luckTrials: trials, luckSeed: UInt64(index) &+ 1)
        var bucket = byWeekday[date.weekday] ?? AuditBucket()
        bucket.add(profile, shape: profile.solutionID)
        byWeekday[date.weekday] = bucket
        dailyFingerprints[profile.fingerprint, default: 0] += 1
        let shapeKey = "\(puzzle.difficulty.rawValue) \(puzzle.par) \(arrows(puzzle.solution))"
        dailyShapes[shapeKey, default: 0] += 1
        if index % 25 == 0 {
            FileHandle.standardError.write(Data("daily \(index + 1)/\(days) \(date.iso)\n".utf8))
        }
        date = date.adding(days: 1)
    }

    print("Daily puzzles: \(days) from \(start.iso), \(trials) random attempts each")
    print("Weekday  n  par  nodes  first  solutions  luck  ≤2 dirs  one-slide  grey décor  wall décor")
    for weekday in PuzzleDate.Weekday.allCases {
        guard let bucket = byWeekday[weekday] else { continue }
        let parSummary = bucket.pars.keys.sorted().map { "\($0):\(bucket.pars[$0]!)" }.joined(separator: " ")
        print([
            "\(weekday)",
            "\(bucket.count)",
            "[\(parSummary)] med \(median(parList(bucket.pars)))",
            "med \(median(bucket.nodes))",
            "med \(median(bucket.firstMoves))",
            "med \(median(bucket.solutions))\(bucket.saturated > 0 ? " sat \(bucket.saturated)" : "")",
            percent(bucket.luckSolves, bucket.luckTrials),
            percent(bucket.twoDirections, bucket.count),
            percent(bucket.oneSlide, bucket.count),
            "\(percent(bucket.decorativeGreys, bucket.withGreys)) of \(bucket.withGreys)",
            "\(percent(bucket.decorativeWalls, bucket.withWalls)) of \(bucket.withWalls)",
        ].joined(separator: "  "))
    }
    let duplicateDays = dailyFingerprints.values.filter { $0 > 1 }.count
    let repeatedShapes = dailyShapes.filter { $0.value > 1 }.count
    print("Exact duplicate layouts across these dates: \(duplicateDays)")
    print("Repeated solution shapes (difficulty + par + moves): \(repeatedShapes)")

    print("\nPractice, \(practiceEach) each, \(trials) random attempts")
    print("Level  par  nodes  first  solutions  luck  ≤2 dirs  one-slide  grey décor  wall décor  dup layouts")
    for difficulty in Difficulty.allCases {
        var bucket = AuditBucket()
        for seed in 0..<practiceEach {
            let puzzle = Generator.practice(seed: UInt64(seed), difficulty: difficulty)
            let profile = PuzzleAudit.profile(puzzle, luckTrials: trials, luckSeed: UInt64(seed) &+ 9)
            bucket.add(profile, shape: profile.solutionID)
            if seed % 50 == 0 {
                FileHandle.standardError.write(Data("\(difficulty.rawValue) \(seed + 1)/\(practiceEach)\n".utf8))
            }
        }
        let parSummary = bucket.pars.keys.sorted().map { "\($0):\(bucket.pars[$0]!)" }.joined(separator: " ")
        let duplicateLayouts = bucket.fingerprints.values.filter { $0 > 1 }.count
        print([
            difficulty.rawValue,
            "[\(parSummary)] med \(median(parList(bucket.pars)))",
            "med \(median(bucket.nodes))",
            "med \(median(bucket.firstMoves))",
            "med \(median(bucket.solutions))\(bucket.saturated > 0 ? " sat \(bucket.saturated)" : "")",
            percent(bucket.luckSolves, bucket.luckTrials),
            percent(bucket.twoDirections, bucket.count),
            percent(bucket.oneSlide, bucket.count),
            "\(percent(bucket.decorativeGreys, bucket.withGreys)) of \(bucket.withGreys)",
            "\(percent(bucket.decorativeWalls, bucket.withWalls)) of \(bucket.withWalls)",
            "\(duplicateLayouts)",
        ].joined(separator: "  "))
        let score = Double(median(parList(bucket.pars)))
            + log2(Double(max(1, median(bucket.nodes)))) / 4
        print("  search score (median par + log2(median nodes) / 4): \(String(format: "%.2f", score))")
    }
}

func runLockAudit(practiceEach: Int) {
    let trials = 12
    print("Lock rule practice, \(practiceEach) each, \(trials) random attempts")
    print("Level  par  nodes  first  solutions  luck  one-slide  first-locks  dead-ends  two-openings")
    for difficulty in Difficulty.allCases {
        var bucket = AuditBucket()
        var deadEnds = 0
        var reachable = 0
        var saturated = 0
        var firstLocks = 0
        var twoOpenings = 0
        for seed in 0..<practiceEach {
            let puzzle = Generator.practice(seed: UInt64(seed), difficulty: difficulty, rules: .locking)
            let profile = PuzzleAudit.profile(puzzle, luckTrials: trials, luckSeed: UInt64(seed) &+ 9)
            bucket.add(profile, shape: profile.solutionID)
            deadEnds += profile.deadEndStates
            reachable += profile.reachableStates
            if profile.deadEndsSaturated { saturated += 1 }
            if profile.firstMoveLocks { firstLocks += 1 }
            if profile.optimalFirstMoves >= 2 { twoOpenings += 1 }
            if seed % 25 == 0 {
                FileHandle.standardError.write(Data("lock \(difficulty.rawValue) \(seed + 1)/\(practiceEach)\n".utf8))
            }
        }
        let parSummary = bucket.pars.keys.sorted().map { "\($0):\(bucket.pars[$0]!)" }.joined(separator: " ")
        print([
            difficulty.rawValue,
            "[\(parSummary)] med \(median(parList(bucket.pars)))",
            "med \(median(bucket.nodes))",
            "med \(median(bucket.firstMoves))",
            "med \(median(bucket.solutions))",
            percent(bucket.luckSolves, bucket.luckTrials),
            percent(bucket.oneSlide, bucket.count),
            percent(firstLocks, bucket.count),
            "\(percent(deadEnds, reachable)) of \(reachable) sat \(saturated)",
            percent(twoOpenings, bucket.count),
        ].joined(separator: "  "))
    }
}
