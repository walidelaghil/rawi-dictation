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
                                 + "accumulated in a counter — delete a dictation and these "
                                 + "change to match. Words per minute is words over time "
                                 + "actually spoken. Time saved is an estimate against a typing "
                                 + "speed you set. Transforms are excluded from the spoken "
                                 + "figures: that text was on your clipboard, not in your voice.")

                if i == .empty {
                    EmptyHint(title: "Nothing to measure yet",
                              detail: "Dictate something and this fills in.",
                              appearance: model.appearance)
                } else {
                    tiles
                    streak
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
                     "spoken, not wall clock", .saffron)
                tile(spokenTime, "time speaking",
                     "microphone open, transcribing excluded", .lapis)
            }
            HStack(spacing: 10) {
                savedTile
                tile("\(i.entriesCleaned)", "cleaned up",
                     i.cleanupsRejected == 0
                        ? "no cleanup was ever rejected"
                        : "\(i.cleanupsRejected) rejected, raw kept instead", .verdigris)
                tile("\(i.activeDays.count)", "days used",
                     "longest run \(i.longestStreak) day\(i.longestStreak == 1 ? "" : "s")",
                     .bone)
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
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(c(.saffron))
                Text("ESTIMATE")
                    .font(.system(size: 8, weight: .medium).monospaced()).tracking(1.1)
                    .foregroundStyle(c(.faint))
            }
            Text("saved versus typing").font(.system(size: 11.5)).foregroundStyle(c(.muted))
            HStack(spacing: 6) {
                Text("at").font(.system(size: 10.5)).foregroundStyle(c(.faint))
                Stepper(value: $model.typingWPM, in: 20...120, step: 1) {
                    Text("\(model.typingWPM) wpm")
                        .font(.system(size: 10.5).monospacedDigit())
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
                .font(.system(size: 26, weight: .semibold).monospacedDigit())
                .foregroundStyle(c(token))
            Text(label).font(.system(size: 11.5)).foregroundStyle(c(.muted))
            Text(detail).font(.system(size: 10.5)).foregroundStyle(c(.faint))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(.edge))))
    }

    // MARK: - Streak

    private var streak: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(i.currentStreak) day\(i.currentStreak == 1 ? "" : "s") running")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(c(.bone))
                Text(i.currentStreak >= i.longestStreak
                        ? "Your longest run so far"
                        : "Your longest was \(i.longestStreak)")
                    .font(.system(size: 11)).foregroundStyle(c(.faint))
            }
            Spacer()
            HStack(spacing: 4) {
                ForEach(lastFortnight, id: \.key) { day in
                    RoundedRectangle(cornerRadius: Radius.mark)
                        .fill(day.active ? c(.saffron) : c(.edge))
                        .frame(width: 11, height: 22)
                        .help(day.key)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(.edge))))
    }

    private var lastFortnight: [(key: String, active: Bool)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<14).reversed().compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: today)
            else { return nil }
            let key = formatter.string(from: date)
            return (key, i.activeDays.contains(key))
        }
    }

    // MARK: - Apps

    private var apps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where you dictate").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(c(.bone))
            ForEach(i.byApp.prefix(8)) { share in
                HStack(spacing: 10) {
                    Text(share.name).font(.system(size: 11.5))
                        .foregroundStyle(c(.muted))
                        .frame(width: 150, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: Radius.mark)
                            .fill(c(.lapis))
                            .frame(width: max(2, geo.size.width * share.share), height: 8)
                            .frame(height: 8, alignment: .leading)
                    }
                    .frame(height: 8)
                    Text("\(Int((share.share * 100).rounded()))%")
                        .font(.system(size: 10.5).monospacedDigit())
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
