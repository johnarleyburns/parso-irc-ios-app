import Foundation

extension Date {
    // MARK: - Cached formatters (DateFormatter is expensive to init)

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let longDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    // MARK: - API

    func timeAgo() -> String {
        Date.relativeFormatter.localizedString(for: self, relativeTo: Date())
    }
    
    func formattedTime() -> String {
        Date.timeFormatter.string(from: self)
    }
    
    func formattedDate() -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self)     { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        return Date.longDateFormatter.string(from: self)
    }
    
    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }
    
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
    
    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }
}
