import DayblockCore

// Usage:
//   dayblock-cli sample [days] [yyyy-mm-dd]   print daily puzzles
//   dayblock-cli stats [count]                par spread and speed per difficulty

func parseDate(_ text: String) -> PuzzleDate? {
    let parts = text.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return PuzzleDate(year: parts[0], month: parts[1], day: parts[2])
}

func nextDay(_ date: PuzzleDate) -> PuzzleDate {
    let lengths = [31, (date.year % 4 == 0 && (date.year % 100 != 0 || date.year % 400 == 0)) ? 29 : 28,
                   31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    if date.day < lengths[date.month - 1] { return PuzzleDate(year: date.year, month: date.month, day: date.day + 1) }
    if date.month < 12 { return PuzzleDate(year: date.year, month: date.month + 1, day: 1) }
    return PuzzleDate(year: date.year + 1, month: 1, day: 1)
}

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
        date = nextDay(date)
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
default:
    print("unknown command \(command)")
}
