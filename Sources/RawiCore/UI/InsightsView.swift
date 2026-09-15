import AppKit
import SwiftUI

public enum InsightsTab: String, CaseIterable, Sendable {
    case usage, voice
    var title: String { self == .usage ? "Your usage" : "Your voice" }
}

@MainActor
public final class InsightsViewModel: ObservableObject {
    @Published public var tab: InsightsTab = .usage
    @Published public var usage: UsageInsights = UsageInsights.compute(from: [])
    @Published public var voice: VoiceInsights = VoiceInsights.compute(from: [])
    @Published public var profile: VoiceProfile?
    @Published public var writingProfile = false
    @Published public var profileProblem: String?
    @Published public var appearance: ResolvedAppearance = .dark
    @Published public var showInfo = false
    /// The baseline the time-saved estimate is measured against, and adjustable,
    /// because a claim about *your* typing speed should be yours to set.
    @Published public var typingWPM: Int = 41

    /// Dictionary spellings, for counting fixes that landed on them.
    public var terms: () -> [String] = { [] }
    /// Words you corrected Rawi into, newest first.
    public var taught: () -> [String] = { [] }
    /// Writes the voice profile: (system prompt, request) to the model's reply.
    /// Nil when no model is available, and the screen says so.
    public var writer: ((String, String) async throws -> String)?
    public var profileStore: VoiceProfileStore?

    private let store: HistoryStore

    public init(store: HistoryStore) {
        self.store = store
        reload()
    }

    public var isEmpty: Bool { usage.dictations == 0 }

    public func reload() {
        let entries = store.all()
        usage = UsageInsights.compute(from: entries, terms: terms())
        voice = VoiceInsights.compute(from: entries, taught: taught())
        if profile == nil { profile = profileStore?.load() }
    }

    /// Whether a new profile is due: enough words since the last one, or none yet
    /// and enough to go on.
    public var profileDue: Bool {
        guard usage.words >= VoiceProfile.minimumWords else { return false }
        guard let profile else { return true }
        return profile.wordsUntilUpdate(currentWords: usage.words) == 0
    }

    public func writeProfileIfDue() {
        if profileDue { writeProfile() }
    }

    public func writeProfile() {
        guard let writer, !writingProfile else { return }
        writingProfile = true
        profileProblem = nil
        let request = VoiceProfile.request(entries: store.all(), voice: voice, usage: usage)
        let words = usage.words
        Task {
            defer { writingProfile = false }
            do {
                let reply = try await writer(VoiceProfile.systemPrompt, request)
                guard let written = VoiceProfile.parse(reply, words: words) else {
                    profileProblem = "The model's answer did not read as a profile, so it was not shown."
                    return
                }
                profile = written
                profileStore?.save(written)
            } catch {
                profileProblem = "Could not reach the model: \(error.localizedDescription)"
            }
        }
    }

    /// The peak sentence to show: the model's, or the counted one when the model's
    /// was missing or ran long.
    public var peakSentence: String? {
        if let written = profile?.peak, !written.isEmpty { return written }
        guard let moment = voice.peakMoment else { return nil }
        return "You dictate most on \(moment)" + (voice.peakApp.map { ", usually in \($0)." } ?? ".")
    }
}

public struct InsightsView: View {
    @ObservedObject var model: InsightsViewModel
    public init(model: InsightsViewModel) { self.model = model }
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, model.appearance) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    ScreenHeader(title: "Insights", appearance: model.appearance,
                                 showInfo: $model.showInfo,
                                 info: "Everything here is worked out on this Mac from your own "
                                     + "history, and changes when history does. Speed is words over "
                                     + "time actually spoken. Time saved is an estimate against a "
                                     + "typing speed you set. Your voice profile is written by the "
                                     + "local model from a sample of your dictations with email "
                                     + "addresses, links and numbers taken out first.",
                                 trailing: AnyView(ShareButton(model: model)))
                }
                tabs
                if model.isEmpty {
                    EmptyHint(title: "Nothing to measure yet",
                              detail: "Dictate something and this fills in.",
                              appearance: model.appearance)
                } else {
                    switch model.tab {
                    case .usage: UsageTab(model: model)
                    case .voice: VoiceTab(model: model)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(c(.surface))
        .onAppear { model.reload() }
    }

    private var tabs: some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                ForEach(InsightsTab.allCases, id: \.self) { tab in
                    Button {
                        model.tab = tab
                        if tab == .voice { model.writeProfileIfDue() }
                    } label: {
                        VStack(spacing: 8) {
                            Text(tab.title)
                                .font(.system(size: TypeScale.body, weight: model.tab == tab ? .semibold : .regular))
                                .foregroundStyle(model.tab == tab ? c(.bone) : c(.muted))
                            Rectangle().fill(model.tab == tab ? c(.saffron) : .clear).frame(height: 2)
                        }
                        .fixedSize()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            Rectangle().fill(c(.edge)).frame(height: 1)
        }
        .animation(.easeOut(duration: 0.15), value: model.tab)
    }
}

// MARK: - Shared pieces

private struct Card<Content: View>: View {
    let appearance: ResolvedAppearance
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Radius.surface)
                .fill(RawiColors.color(.raised, appearance))
                .overlay(RoundedRectangle(cornerRadius: Radius.surface)
                    .strokeBorder(RawiColors.color(.edge, appearance))))
    }
}

private struct Eyebrow: View {
    let text: String
    let appearance: ResolvedAppearance
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: TypeScale.micro, weight: .medium))
            .tracking(1.1)
            .foregroundStyle(RawiColors.color(.faint, appearance))
    }
}

private struct Figure: View {
    let text: String
    var token: ColorToken = .bone
    var size: CGFloat = TypeScale.figure
    let appearance: ResolvedAppearance
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold).monospacedDigit())
            .foregroundStyle(RawiColors.color(token, appearance))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Your usage

private struct UsageTab: View {
    @ObservedObject var model: InsightsViewModel
    private var u: UsageInsights { model.usage }
    private var a: ResolvedAppearance { model.appearance }
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, a) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                speed
                fixes
                words
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                places
                StreakCard(usage: u, appearance: a)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                saved
                languages
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var speed: some View {
        Card(appearance: a) {
            VStack(alignment: .leading, spacing: 4) {
                Figure(text: "\(u.wordsPerMinute)", appearance: a)
                Eyebrow(text: "Words per minute", appearance: a)
                Gauge(fraction: min(1, Double(u.wordsPerMinute) / 160), appearance: a) {
                    VStack(spacing: 1) {
                        Text(String(format: "%.1f×", Double(u.wordsPerMinute) / Double(max(1, model.typingWPM))))
                            .font(.system(size: TypeScale.heading, weight: .semibold).monospacedDigit())
                            .foregroundStyle(c(.bone))
                        Text("your typing").font(.system(size: TypeScale.micro)).foregroundStyle(c(.faint))
                    }
                }
                .frame(height: 78)
                .padding(.top, 8)
                .help("Against typing at \(model.typingWPM) words per minute, set under Time saved")
            }
        }
    }

    private var fixes: some View {
        Card(appearance: a) {
            VStack(alignment: .leading, spacing: 4) {
                Figure(text: (u.wordsTidied + u.dictionaryFixes).formatted(), appearance: a)
                Eyebrow(text: "Fixes made by Rawi", appearance: a)
                Rectangle().fill(c(.edge)).frame(height: 1).padding(.vertical, 10)
                fixRow(u.wordsTidied, "words tidied", "Filler removed, corrections applied, run-ons split")
                fixRow(u.dictionaryFixes, "dictionary spellings", "Words that came out the way your dictionary spells them")
            }
        }
    }

    private func fixRow(_ value: Int, _ label: String, _ help: String) -> some View {
        HStack(spacing: 5) {
            Text(value.formatted()).font(.system(size: TypeScale.body, weight: .semibold).monospacedDigit())
                .foregroundStyle(c(.bone))
            Text(label).font(.system(size: TypeScale.body)).foregroundStyle(c(.muted))
            Spacer()
            Image(systemName: "info.circle").font(.system(size: TypeScale.small)).foregroundStyle(c(.faint))
                .help(help)
        }
        .padding(.vertical, 2)
    }

    private var words: some View {
        Card(appearance: a) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Figure(text: u.words.formatted(), appearance: a)
                    Spacer()
                    if let trend = u.trend {
                        Label("\(Int((abs(trend) * 100).rounded()))% this month",
                              systemImage: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: TypeScale.small, weight: .medium))
                            .foregroundStyle(trend >= 0 ? c(.verdigris) : c(.muted))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(c(.surface)))
                    }
                }
                Eyebrow(text: "Words dictated", appearance: a)
                Rectangle().fill(c(.edge)).frame(height: 1).padding(.vertical, 10)
                Text(u.pages >= 1 ? "About \(u.pages.formatted()) \(u.pages == 1 ? "page" : "pages") of writing."
                                  : "Your first page of writing is on its way.")
                    .font(.system(size: TypeScale.body)).foregroundStyle(c(.bone))
                Text("\(u.dictations.formatted()) dictations across \(u.appsUsed) \(u.appsUsed == 1 ? "app" : "apps")")
                    .font(.system(size: TypeScale.small)).foregroundStyle(c(.faint))
            }
        }
    }

    private var places: some View {
        Card(appearance: a) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Where you dictate").font(.system(size: TypeScale.title, weight: .semibold))
                        .foregroundStyle(c(.bone))
                    Spacer()
                    Eyebrow(text: "Apps used  \(u.appsUsed)", appearance: a)
                }
                ForEach(Array(u.places.prefix(6).enumerated()), id: \.element.id) { index, place in
                    HStack(spacing: 10) {
                        Image(systemName: place.place.symbol)
                            .font(.system(size: TypeScale.body))
                            .foregroundStyle(c(.muted))
                            .frame(width: 18)
                        GeometryReader { geo in
                            let width = max(6, geo.size.width * place.share)
                            let inside = width >= 46
                            HStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: Radius.mark)
                                        .fill(c(.saffron).opacity(index == 0 ? 1 : 0.62))
                                    if inside {
                                        Text("\(Int((place.share * 100).rounded()))%")
                                            .font(.system(size: TypeScale.micro, weight: .semibold).monospacedDigit())
                                            .foregroundStyle(a == .dark ? RawiColors.color(.ink, .dark)
                                                                        : RawiColors.color(.surface, .light))
                                    }
                                }
                                .frame(width: width)
                                if !inside {
                                    Text("\(Int((place.share * 100).rounded()))%")
                                        .font(.system(size: TypeScale.micro, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(c(.muted))
                                }
                            }
                        }
                        .frame(height: 22)
                        Text("\(place.dictations.formatted()) \(place.place.label(count: place.dictations).uppercased())")
                            .font(.system(size: TypeScale.micro, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(c(.bone))
                            .lineLimit(1)
                            .frame(width: 160, alignment: .leading)
                    }
                }
            }
        }
    }

    private var saved: some View {
        let minutes = u.minutesSaved(typingWPM: model.typingWPM)
        return Card(appearance: a) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Figure(text: minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m",
                           token: .saffron, appearance: a)
                    Eyebrow(text: "Estimate", appearance: a)
                }
                Eyebrow(text: "Time saved against typing", appearance: a)
                HStack(spacing: 6) {
                    Text("if you type at").font(.system(size: TypeScale.small)).foregroundStyle(c(.faint))
                    Stepper(value: $model.typingWPM, in: 20...120, step: 1) {
                        Text("\(model.typingWPM) wpm").font(.system(size: TypeScale.small).monospacedDigit())
                            .foregroundStyle(c(.muted))
                    }
                    .controlSize(.mini)
                }
                .padding(.top, 8)
            }
        }
    }

    private var languages: some View {
        Card(appearance: a) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Figure(text: "\(Int((u.arabicShare * 100).rounded()))%", token: .lapis, appearance: a)
                    Text("of your words are Arabic").font(.system(size: TypeScale.body)).foregroundStyle(c(.bone))
                }
                GeometryReader { geo in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: Radius.mark).fill(c(.lapis))
                            .frame(width: max(3, (geo.size.width - 3) * u.arabicShare))
                        RoundedRectangle(cornerRadius: Radius.mark).fill(c(.saffron).opacity(0.75))
                    }
                }
                .frame(height: 8)
                HStack {
                    Text("العربية \(u.arabicWords.formatted())").font(.system(size: TypeScale.small)).foregroundStyle(c(.lapis))
                    Spacer()
                    Text("\(u.latinWords.formatted()) English").font(.system(size: TypeScale.small)).foregroundStyle(c(.muted))
                }
                Text(u.mixedDictations == 0
                     ? "One key hears both languages."
                     : "You switched languages mid-dictation \(u.mixedDictations) \(u.mixedDictations == 1 ? "time" : "times").")
                    .font(.system(size: TypeScale.small)).foregroundStyle(c(.faint))
            }
        }
    }
}

/// A half circle filled to a fraction, with something in its middle.
private struct Gauge<Center: View>: View {
    let fraction: Double
    let appearance: ResolvedAppearance
    @ViewBuilder var center: Center

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height * 2)
            let line: CGFloat = 12
            ZStack {
                Arc(fraction: 1).stroke(RawiColors.color(.edge, appearance),
                                         style: StrokeStyle(lineWidth: line, lineCap: .round))
                Arc(fraction: fraction).stroke(RawiColors.color(.saffron, appearance),
                                                style: StrokeStyle(lineWidth: line, lineCap: .round))
                center.offset(y: side * 0.12)
            }
            .frame(width: side, height: side / 2 + line / 2)
            .frame(maxWidth: .infinity)
        }
    }

    private struct Arc: Shape {
        let fraction: Double
        func path(in rect: CGRect) -> Path {
            let line: CGFloat = 12
            let radius = rect.width / 2 - line / 2
            var path = Path()
            path.addArc(center: CGPoint(x: rect.midX, y: rect.maxY - line / 2), radius: radius,
                        startAngle: .degrees(180), endAngle: .degrees(180 + 180 * max(0.001, fraction)),
                        clockwise: false)
            return path
        }
    }
}

/// Days as a grid of weeks, lit by how much you said.
private struct StreakCard: View {
    let usage: UsageInsights
    let appearance: ResolvedAppearance
    static let weeks = 17
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, appearance) }

    private struct Day: Identifiable {
        let id: String
        let date: Date
        let words: Int
        let future: Bool
    }

    private var grid: [[Day]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)            // 1 = Sunday
        guard let lastSaturday = calendar.date(byAdding: .day, value: 7 - weekday, to: today),
              let start = calendar.date(byAdding: .day, value: -(Self.weeks * 7 - 1), to: lastSaturday)
        else { return [] }
        let key = DateFormatter(); key.dateFormat = "yyyy-MM-dd"
        return (0..<Self.weeks).map { week in
            (0..<7).compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: week * 7 + offset, to: start) else { return nil }
                let id = key.string(from: date)
                return Day(id: id, date: date, words: usage.wordsByDay[id] ?? 0, future: date > today)
            }
        }
    }

    private func fill(_ day: Day, max: Int) -> Color {
        if day.future { return .clear }
        guard day.words > 0, max > 0 else { return c(.edge).opacity(0.45) }
        let level = Double(day.words) / Double(max)
        return c(.saffron).opacity(level > 0.75 ? 1 : level > 0.4 ? 0.72 : level > 0.15 ? 0.48 : 0.28)
    }

    var body: some View {
        let weeks = grid
        let busiest = usage.wordsByDay.values.max() ?? 0
        let cell: CGFloat = 13, gap: CGFloat = 4
        let month = DateFormatter(); month.dateFormat = "MMM"
        let calendar = Calendar.current
        let todayKey: String = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date()) }()
        return Card(appearance: appearance) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(usage.currentStreak) day streak")
                        .font(.system(size: TypeScale.title, weight: .semibold)).foregroundStyle(c(.bone))
                    Spacer()
                    Eyebrow(text: "Longest streak  \(usage.longestStreak) \(usage.longestStreak == 1 ? "day" : "days")",
                            appearance: appearance)
                }
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .trailing, spacing: gap) {
                        Text(" ").font(.system(size: TypeScale.micro)).frame(height: 12)
                        ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { name in
                            Text(name).font(.system(size: TypeScale.micro)).foregroundStyle(c(.faint))
                                .frame(height: cell)
                        }
                    }
                    VStack(alignment: .leading, spacing: gap) {
                        HStack(spacing: gap) {
                            ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                                let first = week.first?.date ?? Date()
                                let newMonth = index == 0
                                    || calendar.component(.month, from: first)
                                        != calendar.component(.month, from: weeks[index - 1].first?.date ?? first)
                                Color.clear
                                    .frame(width: cell, height: 12)
                                    .overlay(alignment: .leading) {
                                        if newMonth {
                                            Text(month.string(from: first))
                                                .font(.system(size: TypeScale.micro)).foregroundStyle(c(.faint))
                                                .fixedSize()
                                        }
                                    }
                            }
                        }
                        HStack(spacing: gap) {
                            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                                VStack(spacing: gap) {
                                    ForEach(week) { day in
                                        RoundedRectangle(cornerRadius: Radius.mark)
                                            .fill(fill(day, max: busiest))
                                            .overlay(RoundedRectangle(cornerRadius: Radius.mark)
                                                .strokeBorder(day.id == todayKey ? c(.bone) : .clear, lineWidth: 1.5))
                                            .frame(width: cell, height: cell)
                                            .help(day.future ? "" : "\(day.id): \(day.words) words")
                                    }
                                }
                            }
                        }
                    }
                }
                HStack(spacing: 5) {
                    Text("Less").font(.system(size: TypeScale.micro)).foregroundStyle(c(.faint))
                    ForEach([0.28, 0.48, 0.72, 1.0], id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2).fill(c(.saffron).opacity(level)).frame(width: 10, height: 10)
                    }
                    Text("More").font(.system(size: TypeScale.micro)).foregroundStyle(c(.faint))
                    Spacer()
                    RoundedRectangle(cornerRadius: 2).strokeBorder(c(.bone), lineWidth: 1.5).frame(width: 10, height: 10)
                    Text("Today").font(.system(size: TypeScale.micro)).foregroundStyle(c(.faint))
                }
            }
        }
    }
}

// MARK: - Your voice

private struct VoiceTab: View {
    @ObservedObject var model: InsightsViewModel
    private var v: VoiceInsights { model.voice }
    private var a: ResolvedAppearance { model.appearance }
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, a) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            progress
            profileCard
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    quote(v.catchphrase.map { "\u{201C}\($0)\u{201D}" } ?? "Not yet", "Catchphrase",
                          v.catchphrase == nil ? "A phrase you say three times becomes one." : nil)
                    quote(v.mostUsedWord.map { "\u{201C}\($0)\u{201D}" } ?? "Not yet", "Most used word", nil)
                    quote(v.mostCorrectedWord.map { "\u{201C}\($0)\u{201D}" } ?? "Nothing yet", "Most corrected word",
                          model.taught().first == v.mostCorrectedWord && v.mostCorrectedWord != nil
                            ? "You taught Rawi this spelling." : nil)
                }
                peak
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                quote(v.filler.map { "\u{201C}\($0.word)\u{201D}" } ?? "None", "Your filler",
                      v.filler.map { "Rawi took it out \($0.count) \($0.count == 1 ? "time" : "times")." })
                quote("\(v.longestDictationWords.formatted()) words", "Longest dictation", nil)
                quote("\(model.taught().count)", "Words you taught Rawi",
                      model.taught().isEmpty ? "Fix a spelling after Rawi types it." : model.taught().prefix(3).joined(separator: ", "))
            }
            .fixedSize(horizontal: false, vertical: true)
            Text("Your dictations are private and stay on this Mac. This page is worked out here, from your own history.")
                .font(.system(size: TypeScale.small)).italic()
                .foregroundStyle(c(.faint))
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
        }
        .onAppear { model.writeProfileIfDue() }
    }

    private var progress: some View {
        let profile = model.profile
        let remaining = profile?.wordsUntilUpdate(currentWords: model.usage.words)
            ?? max(0, VoiceProfile.minimumWords - model.usage.words)
        let span = Double(profile == nil ? VoiceProfile.minimumWords : VoiceProfile.refreshEvery)
        let fraction = 1 - Double(remaining) / span
        return VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(c(.edge))
                    Capsule().fill(c(.saffron)).frame(width: max(6, geo.size.width * min(1, max(0, fraction))))
                }
            }
            .frame(height: 6)
            HStack {
                Text(profile.map { "Written \($0.createdAt.formatted(date: .abbreviated, time: .omitted))" }
                     ?? "Your profile is written once you have said \(VoiceProfile.minimumWords) words")
                    .font(.system(size: TypeScale.small)).foregroundStyle(c(.muted))
                Spacer()
                Text(remaining == 0 ? "Ready to update" : "Next update in \(remaining.formatted()) more words")
                    .font(.system(size: TypeScale.small)).foregroundStyle(c(.faint))
                    .help("Rewritten every \(VoiceProfile.refreshEvery.formatted()) words, so it follows how you change")
            }
        }
    }

    private var profileCard: some View {
        Card(appearance: a) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    if let profile = model.profile {
                        Text(profile.archetype)
                            .font(.system(size: TypeScale.hero, weight: .semibold))
                            .foregroundStyle(c(.bone))
                            .fixedSize(horizontal: false, vertical: true)
                        Eyebrow(text: "Voice profile", appearance: a)
                        Text(profile.summary)
                            .font(.system(size: TypeScale.heading))
                            .foregroundStyle(c(.bone))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    } else if model.writingProfile {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Reading your dictations…").font(.system(size: TypeScale.heading)).foregroundStyle(c(.muted))
                        }
                    } else {
                        Text(model.writer == nil ? "Voice profile needs a model" : "Not written yet")
                            .font(.system(size: TypeScale.title, weight: .semibold)).foregroundStyle(c(.bone))
                        Text(model.writer == nil
                             ? "Turn on polish in Settings, and the local model writes a short read of how you use your voice."
                             : "It is written once you have said \(VoiceProfile.minimumWords) words.")
                            .font(.system(size: TypeScale.body)).foregroundStyle(c(.muted))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let problem = model.profileProblem {
                        Text(problem).font(.system(size: TypeScale.small)).foregroundStyle(c(.clay))
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 10) {
                    RawiMarkShape()
                        .stroke(c(.saffron), style: RawiMarkShape.stroke(for: 84))
                        .frame(width: 84, height: 84)
                        .accessibilityHidden(true)
                    if model.writer != nil, model.usage.words >= VoiceProfile.minimumWords {
                        Button { model.writeProfile() } label: {
                            Label(model.profile == nil ? "Write it now" : "Rewrite", systemImage: "arrow.clockwise")
                                .font(.system(size: TypeScale.small)).foregroundStyle(c(.muted))
                        }
                        .buttonStyle(.plain)
                        .disabled(model.writingProfile)
                    }
                }
            }
        }
    }

    private func quote(_ value: String, _ label: String, _ detail: String?) -> some View {
        Card(appearance: a) {
            VStack(alignment: .leading, spacing: 5) {
                Text(value)
                    .font(.system(size: TypeScale.title, weight: .semibold))
                    .foregroundStyle(c(.bone))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Eyebrow(text: label, appearance: a)
                if let detail {
                    Text(detail).font(.system(size: TypeScale.small)).foregroundStyle(c(.faint))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var peak: some View {
        Card(appearance: a) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: TypeScale.heading, weight: .semibold))
                    .foregroundStyle(a == .dark ? RawiColors.color(.ink, .dark) : RawiColors.color(.surface, .light))
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.saffron)))
                    .padding(.bottom, 14)
                Text(v.peakMoment ?? "Not yet")
                    .font(.system(size: TypeScale.title, weight: .semibold)).foregroundStyle(c(.bone))
                Eyebrow(text: "Your peak time and place", appearance: a)
                if let sentence = model.peakSentence {
                    Text(sentence).font(.system(size: TypeScale.heading)).foregroundStyle(c(.bone))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
            }
        }
    }
}

// MARK: - Share

/// Renders the open tab to an image and offers it to the system share menu.
private struct ShareButton: View {
    @ObservedObject var model: InsightsViewModel
    @State private var anchor: NSView?
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, model.appearance) }

    var body: some View {
        Button(action: share) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: TypeScale.body, weight: .medium))
                .foregroundStyle(c(.muted))
                .frame(width: 30, height: 30)
                .background(Circle().fill(c(.raised)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Share this page as an image")
        .background(AnchorView(view: $anchor))
        .disabled(model.isEmpty)
    }

    @MainActor private func share() {
        let content = VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                RawiMarkShape().stroke(RawiColors.color(.saffron, model.appearance),
                                       style: RawiMarkShape.stroke(for: 18)).frame(width: 18, height: 18)
                Wordmark(appearance: model.appearance)
                Spacer()
                Text(model.tab.title).font(.system(size: TypeScale.body)).foregroundStyle(c(.muted))
            }
            switch model.tab {
            case .usage: UsageTab(model: model)
            case .voice: VoiceTab(model: model)
            }
        }
        .padding(24)
        .frame(width: 760)
        .background(c(.surface))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage, let anchor else { return }
        NSSharingServicePicker(items: [image]).show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    private struct AnchorView: NSViewRepresentable {
        @Binding var view: NSView?
        func makeNSView(context: Context) -> NSView {
            let v = NSView()
            DispatchQueue.main.async { view = v }
            return v
        }
        func updateNSView(_ nsView: NSView, context: Context) {}
    }
}
