import Foundation

public enum ScreenTimeCalendar {

	public static func isSameUsageDay(_ lhs: Date, _ rhs: Date, calendar: Calendar = .current) -> Bool {
		calendar.isDate(lhs, inSameDayAs: rhs)
	}

	public static func minutesFromMidnight(for date: Date, calendar: Calendar = .current) -> Int {
		let components = calendar.dateComponents([.hour, .minute], from: date)
		return (components.hour ?? 0) * 60 + (components.minute ?? 0)
	}

	public static func isWithinBedtimeWindow(_ date: Date, startMinutes: Int, endMinutes: Int, calendar: Calendar = .current) -> Bool {
		guard startMinutes != endMinutes else { return false }
		let minutes = minutesFromMidnight(for: date, calendar: calendar)
		if startMinutes < endMinutes {
			return minutes >= startMinutes && minutes < endMinutes
		}
		return minutes >= startMinutes || minutes < endMinutes
	}
}
