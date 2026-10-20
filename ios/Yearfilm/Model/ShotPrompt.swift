import Foundation

/// The week's suggestion. The film can only be as good as what was filmed, so the
/// weekly nudge is a shot list, not "upload your videos".
enum ShotPrompt {
    static let craft = [
        "Turn your phone sideways and hold one shot for ten seconds.",
        "Film someone reacting — not the thing, the face watching it.",
        "One wide shot of where you are, before anything happens.",
        "Film hands doing something: cooking, building, drawing.",
        "Get a conversation. Let it run — the best line comes late.",
        "Film the walk there, not just the arrival.",
        "Ask someone what their week was like. Film the answer.",
        "Film a laugh from the start — keep rolling after the joke.",
        "Shoot something from very low, at a kid’s eye level.",
        "Film the quiet end of the day.",
    ]

    static let seasonal: [Season: [String]] = [
        .winter: ["First snow, or the coldest morning.", "A warm drink, steam and all, on a cold day."],
        .spring: ["Something growing — a garden, a kid, a puppy.", "Open the windows. Film the first warm afternoon."],
        .summer: ["The road trip: the car, the snacks, the view out the window.", "Water — a pool, a sprinkler, the beach."],
        .fall: ["Back-to-school morning, at the door.", "Leaves, costumes, the first fire of the year."],
        .holidays: ["Decorating — the mess as much as the result.", "The table, before everyone sits down."],
    ]

    /// Deterministic: the same week always gets the same prompt, on every device in the family.
    static func forWeek(_ week: FilmWeek, calendar: Calendar = .current) -> String {
        let pool = (seasonal[week.season(calendar: calendar)] ?? []) + craft
        return pool[(week.week - 1) % pool.count]
    }
}
