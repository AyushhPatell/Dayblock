/// A calendar day, independent of time zones. The app decides which local
/// day it is; the core only does arithmetic on it.
public struct PuzzleDate: Hashable, Codable, Comparable, Sendable {
    public enum Weekday: Int, CaseIterable, Sendable {
        case monday, tuesday, wednesday, thursday, friday, saturday, sunday
    }

    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        precondition((1...12).contains(month) && (1...31).contains(day), "invalid date")
        self.year = year
        self.month = month
        self.day = day
    }

    /// Days since 1970-01-01.
    public var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    public var weekday: Weekday {
        // 1970-01-01 was a Thursday.
        let index = ((dayNumber + 3) % 7 + 7) % 7
        return Weekday(rawValue: index)!
    }

    /// "2026-11-14"
    public var iso: String {
        func pad(_ value: Int, _ width: Int) -> String {
            let text = String(value)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    /// Puzzle number shown to players: 1 on `launch`, 2 the day after, and so on.
    /// Never below 1, so a device with its clock set before launch still shows a sane number.
    public func puzzleNumber(launch: PuzzleDate) -> Int {
        max(1, dayNumber - launch.dayNumber + 1)
    }

    public static func < (a: PuzzleDate, b: PuzzleDate) -> Bool { a.dayNumber < b.dayNumber }
}
