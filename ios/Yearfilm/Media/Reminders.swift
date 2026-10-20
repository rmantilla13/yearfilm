import Foundation
import UserNotifications

/// The weekly nudge: Sunday at 6pm, carrying that week's shot prompt.
///
/// Scheduled as individual one-off notifications for the next few weeks rather than
/// one repeating trigger, because a repeating notification can't change its text and
/// the prompt changes every week. Topped up whenever the app opens.
enum Reminders {
    static let weeksAhead = 8
    static let idPrefix = "weekly-"

    /// Asks for permission - only ever from a button the person pressed - then schedules.
    static func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        if granted { await schedule() }
        return granted
    }

    static func disable() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: (0..<weeksAhead).map { "\(idPrefix)\($0)" })
    }

    /// Next `count` Sunday-6pm dates strictly after `now`. Pure, so it can be tested.
    static func dates(after now: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        guard let first = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 18, minute: 0, weekday: 1),
            matchingPolicy: .nextTime
        ) else { return [] }
        return (0..<count).compactMap { calendar.date(byAdding: .weekOfYear, value: $0, to: first) }
    }

    static func schedule(from now: Date = .now, calendar: Calendar = .current) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }
        disable()
        for (i, date) in dates(after: now, count: weeksAhead, calendar: calendar).enumerated() {
            let week = FilmWeek(date: date, calendar: calendar)
            let content = UNMutableNotificationContent()
            content.title = "Week \(week.week) of your film"
            content.body = "Add this week’s clips. Shot to try: \(ShotPrompt.forWeek(week, calendar: calendar))"
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let request = UNNotificationRequest(
                identifier: "\(idPrefix)\(i)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            )
            try? await center.add(request)
        }
    }
}
