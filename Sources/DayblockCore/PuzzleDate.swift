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
        precondition(Self.isValid(year: year, month: month, day: day), "invalid date")
        self.year = year
        self.month = month
        self.day = day
    }

    /// A real Gregorian day: 1900 is not a leap year, 2000 is.
    public static func isValid(year: Int, month: Int, day: Int) -> Bool {
        guard (1...12).contains(month) else { return false }
        return (1...daysInMonth(month, year: year)).contains(day)
    }

    public static func isLeapYear(_ year: Int) -> Bool {
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }

    public static func daysInMonth(_ month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return 0
        }
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

    /// The day `days` later. Negative values step backward. Built from the same
    /// day count as `dayNumber`, so it stays on the Gregorian calendar.
    public func adding(days: Int) -> PuzzleDate {
        PuzzleDate(dayNumber: dayNumber + days)
    }

    /// Inverse of `dayNumber`. `0` is 1970-01-01.
    public init(dayNumber: Int) {
        let z = dayNumber + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp + (mp < 10 ? 3 : -9)
        self.init(year: y + (month <= 2 ? 1 : 0), month: month, day: day)
    }

    public static func < (a: PuzzleDate, b: PuzzleDate) -> Bool { a.dayNumber < b.dayNumber }
}
