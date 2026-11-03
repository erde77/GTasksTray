import SwiftUI

struct TaskCalendar: View {
    @Binding var selection: Date
    let finish: () -> Void

    @Environment(\.calendar) private var systemCalendar
    @Environment(\.locale) private var locale
    @State private var displayedMonth: Date?

    private var calendar: Calendar {
        var calendar = systemCalendar
        calendar.locale = locale
        return calendar
    }

    var body: some View {
        let calendar = calendar
        let month = displayedMonth ?? selection
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(month, format: .dateTime.month(.wide).year())
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                monthButton(offset: -1, symbol: "chevron.left", label: "Poprzedni miesiąc")
                monthButton(offset: 1, symbol: "chevron.right", label: "Następny miesiąc")
            }

            LazyVGrid(columns: columns, spacing: 4) {
                let symbols = calendar.shortStandaloneWeekdaySymbols
                ForEach(0..<7) { column in
                    Text(symbols[(calendar.firstWeekday - 1 + column) % 7])
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                let days = days(in: month, calendar: calendar)
                ForEach(days.indices, id: \.self) { index in
                    if let day = days[index] {
                        dayButton(day, calendar: calendar)
                    } else {
                        Color.clear.frame(height: 26).accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(12)
        .panelCard()
    }

    private func monthButton(offset: Int, symbol: String, label: LocalizedStringKey) -> some View {
        Button {
            guard let start = calendar.dateInterval(of: .month, for: displayedMonth ?? selection)?.start else { return }
            displayedMonth = calendar.date(byAdding: .month, value: offset, to: start)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 25, height: 25)
                .background(.primary.opacity(0.055), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func dayButton(_ day: Date, calendar: Calendar) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(day)
        return Button {
            selection = day
            finish()
        } label: {
            Text(day, format: .dateTime.day())
                .font(.system(size: 12, weight: isSelected || isToday ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isSelected || isToday ? Color.accentColor : Color.primary)
                .frame(width: 28, height: 26)
                .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: Capsule())
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day().month(.wide).year()))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func days(in month: Date, calendar: Calendar) -> [Date?] {
        guard let start = calendar.dateInterval(of: .month, for: month)?.start,
              let days = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: start)
        let padding = (firstWeekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: padding) + (0..<days.count).map {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }
}
