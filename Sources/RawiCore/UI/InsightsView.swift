import SwiftUI

@MainActor
public final class InsightsViewModel: ObservableObject {
    @Published public var insights: Insights = .empty
    @Published public var appearance: ResolvedAppearance = .dark
    @Published public var showInfo = false
    /// The baseline the time-saved estimate is measured against, and adjustable,
    /// because a claim about *your* typing speed should be yours to set.
    @Published public var typingWPM: Int = 41

    private let store: HistoryStore
    public init(store: HistoryStore) {
        self.store = store
        reload()
    }

    public func reload() { insights = Insights.compute(from: store.all()) }
}

public struct InsightsView: View {
    @ObservedObject var model: InsightsViewModel
    public init(model: InsightsViewModel) { self.model = model }
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, model.appearance) }

    private var i: Insights { model.insights }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Insights", appearance: model.appearance,
                             showInfo: $model.showInfo,
                             info: "Every number here is computed from your history, not "
                                 + "accumulated in a counter, so deleting a dictation changes them "
                                 + "change to match. Words per minute is words over time "
                                 + "actually spoken. Time saved is an estimate against a typing "
                                 + "speed you set. Transforms are excluded from the spoken "
                                 + "figures: that text was on your clipboard, not in your voice.")

                if i == .empty {
                    EmptyHint(title: "Nothing to measure yet",
                              detail: "Dictate something and this fills in.",
                              appearance: model.appearance)
                } else {
                    streak
                    tiles
                    apps
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(c(.surface))
    }

    // MARK: - Tiles

    private var tiles: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                tile("\(i.wordsDictated.formatted())", "words dictated",
                     "across \(i.dictations.formatted()) dictations", .bone)
                tile("\(i.wordsPerMinute)", "words per minute",
                     "spoken, not wall clock", .bone)
                tile(spokenTime, "time speaking",
                     "microphone open, transcribing excluded", .bone)
            }
            HStack(spacing: 10) {
                savedTile
                tile("\(i.entriesCleaned)", "cleaned up",
                     i.cleanupsRejected == 0
                        ? "no cleanup was ever rejected"
                        : "\(i.cleanupsRejected) rejected, raw kept instead", .verdigris)
                tile("\(i.activeDays.count)", "days used",
                     "since you started", .bone)
            }
        }
    }

    private var spokenTime: String {
        let minutes = Int((i.secondsSpoken / 60).rounded())
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    /// The one estimate on the screen, and it says so — with the assumption it
    /// rests on exposed and editable rather than buried.
    private var savedTile: some View {
        let saved = i.minutesSavedVersusTyping(at: model.typingWPM)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(saved < 60 ? "\(saved)m" : "\(saved / 60)h \(saved % 60)m")
                    .font(.system(size: TypeScale.figure, weight: .semibold))
                    .foregroundStyle(c(.saffron))
                Text("ESTIMATE")
                    .font(.system(size: TypeScale.micro, weight: .medium).monospaced()).tracking(1.1)
                    .foregroundStyle(c(.faint))
            }
            Text("saved versus typing").font(.system(size: TypeScale.small)).foregroundStyle(c(.muted))
            HStack(spacing: 6) {
                Text("at").font(.system(size: TypeScale.small)).foregroundStyle(c(.faint))
                Stepper(value: $model.typingWPM, in: 20...120, step: 1) {
                    Text("\(model.typingWPM) wpm")
                        .font(.system(size: TypeScale.small).monospacedDigit())
                        .foregroundStyle(c(.muted))
                }
                .controlSize(.mini)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(.edge))))
    }

    private func tile(_ value: String, _ label: String,
                      _ detail: String, _ token: ColorToken) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: TypeScale.figure, weight: .semibold).monospacedDigit())
                .foregroundStyle(c(token))
            Text(label).font(.system(size: TypeScale.small)).foregroundStyle(c(.muted))
            Text(detail).font(.system(size: TypeScale.small)).foregroundStyle(c(.faint))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(.edge))))
    }

    // MARK: - Streak

    private var streak: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(i.currentStreak)")
                    .font(.system(size: TypeScale.hero, weight: .semibold).monospacedDigit())
                    .foregroundStyle(c(.saffron))
                VStack(alignment: .leading, spacing: 2) {
                    Text(i.currentStreak == 1 ? "day running" : "days running")
                        .font(.system(size: TypeScale.body)).foregroundStyle(c(.bone))
                    Text(i.currentStreak >= i.longestStreak
                            ? "your longest run so far"
                            : "your longest was \(i.longestStreak)")
                        .font(.system(size: TypeScale.small)).foregroundStyle(c(.faint))
                }
                Spacer()
            }

            // Eight weeks of days, one column per week, oldest on the left. This
            // is the only picture on the screen, so it gets the room: the tiles
            // below are numbers you check, this is a shape you recognise.
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(weeks, id: \.first!.key) { week in
                    VStack(spacing: 4) {
                        ForEach(week, id: \.key) { day in
                            // The unlit days are a faint field, not inventory to
                            // count: the shape you are meant to see is the run.
                            RoundedRectangle(cornerRadius: Radius.mark)
                                .fill(day.active ? c(.saffron) : c(.edge).opacity(0.3))
                                .frame(width: 13, height: 13)
                                .help(day.key)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(.edge))))
    }

    /// Eight weeks ending today, as columns of seven.
    private var weeks: [[(key: String, active: Bool)]] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = Calendar.current.startOfDay(for: Date())
        let days: [(key: String, active: Bool)] = (0..<56).reversed().compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: today)
            else { return nil }
            let key = formatter.string(from: date)
            return (key, i.activeDays.contains(key))
        }
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    // MARK: - Apps

    private var apps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where you dictate").font(.system(size: TypeScale.body, weight: .semibold))
                .foregroundStyle(c(.bone))
            ForEach(i.byApp.prefix(8)) { share in
                HStack(spacing: 10) {
                    Text(share.name).font(.system(size: TypeScale.small))
                        .foregroundStyle(c(.muted))
                        .frame(width: 150, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: Radius.mark)
                            .fill(c(.saffron).opacity(share.share >= 0.25 ? 0.9 : 0.55))
                            .frame(width: max(2, geo.size.width * share.share), height: 8)
                            .frame(height: 8, alignment: .leading)
                    }
                    .frame(height: 8)
                    Text("\(Int((share.share * 100).rounded()))%")
                        .font(.system(size: TypeScale.small).monospacedDigit())
                        .foregroundStyle(c(.faint))
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(.edge))))
    }
}
