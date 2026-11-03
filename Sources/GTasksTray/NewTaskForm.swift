import SwiftUI

struct NewTaskForm: View {
    private enum DateChoice {
        case tomorrow, dayAfterTomorrow, custom
    }

    @ObservedObject var store: TaskStore
    let close: () -> Void

    @Environment(\.calendar) private var calendar
    @State private var title = ""
    @State private var notes = ""
    @State private var listID = ""
    @State private var hasDueDate = false
    @State private var dateChoice: DateChoice = .tomorrow
    @State private var dueDate = Date()
    @State private var calendarOpen = false
    @FocusState private var titleFocused: Bool

    private var language: AppLanguage { store.language }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedNotes: String { notes.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var tooLong: Bool { trimmedTitle.utf16.count > 1024 || trimmedNotes.utf16.count > 8192 }
    private var canSave: Bool {
        !trimmedTitle.isEmpty && !tooLong && !store.isBusy
            && store.groups.contains { $0.id == listID }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    if !calendarOpen {
                        editor
                    }
                    details
                    if calendarOpen {
                        TaskCalendar(selection: $dueDate, language: language) { calendarOpen = false }
                    }
                    if tooLong {
                        Label(language.text("The title can be up to 1,024 characters and the note up to 8,192."), systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(PanelStyle.inset)
                .disabled(store.isSaving)
            }
            Divider()
            actions
        }
        .onAppear {
            if listID.isEmpty { listID = store.groups.first?.id ?? "" }
            titleFocused = true
        }
        .onChange(of: store.groups.map(\.id)) { ids in
            if !ids.contains(listID) { listID = ids.first ?? "" }
        }
        .onChange(of: hasDueDate) { enabled in
            if !enabled { calendarOpen = false }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(language.text("What needs to be done?"), text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .semibold))
                .focused($titleFocused)
                .accessibilityLabel(language.text("Task title"))
                .onSubmit(save)
                .padding(.horizontal, 15)
                .padding(.vertical, 16)

            Divider().padding(.horizontal, 15)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel(language.text("Task note"))
                if notes.isEmpty {
                    Text(language.text("Add a note (optional)"))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 5)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .font(.system(size: 13))
            .frame(height: 112)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
        }
        .panelCard()
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !calendarOpen {
                Text(language.text("Details"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                if !calendarOpen {
                    HStack {
                        fieldLabel(language.text("List"), icon: "list.bullet", color: .accentColor)
                        Spacer(minLength: 10)
                        Picker(language.text("List"), selection: $listID) {
                            ForEach(store.groups) { group in
                                Text(group.list.title).tag(group.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 190, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 45)

                    Divider().padding(.leading, 45)
                }

                HStack {
                    fieldLabel(language.text("With a date"), icon: "calendar", color: .orange)
                    Spacer(minLength: 10)
                    Toggle(language.text("With a date"), isOn: $hasDueDate)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 45)

                if hasDueDate {
                    dateOptions
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    if dateChoice == .custom, !calendarOpen {
                        Text(dueDate, format: .dateTime.day().month(.wide).year())
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                    }
                }
            }
            .panelCard()
        }
    }

    private var dateOptions: some View {
        HStack(spacing: 7) {
            datePill(language.text("Tomorrow"), icon: "sunrise", choice: .tomorrow)
            datePill(language.text("In two days"), icon: "sun.max", choice: .dayAfterTomorrow)
            datePill(language.text("Date"), icon: "calendar", choice: .custom)
        }
    }

    private func datePill(_ title: String, icon: String, choice: DateChoice) -> some View {
        let selected = dateChoice == choice
        return Button {
            if choice == .custom, dateChoice != .custom {
                dueDate = selectedDate ?? Date()
            }
            dateChoice = choice
            calendarOpen = choice == .custom && !calendarOpen
        } label: {
            Label(title, systemImage: selected ? "checkmark" : icon)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 31)
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .background(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.055), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var selectedDate: Date? {
        switch dateChoice {
        case .tomorrow:
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
        case .dayAfterTomorrow:
            calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: Date()))
        case .custom:
            dueDate
        }
    }

    private func fieldLabel(_ title: String, icon: String, color: Color) -> some View {
        Label {
            Text(title).font(.system(size: 13, weight: .medium))
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 25, height: 25)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Spacer()
            if store.isSaving {
                ProgressView().controlSize(.small)
                    .accessibilityLabel(language.text("Saving task"))
            }
            Button(language.text("Cancel"), action: close)
                .panelButton()
                .keyboardShortcut(.cancelAction)
                .disabled(store.isSaving)
            AddTaskButton(language.text("Add task"), action: save)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSave)
        }
        .controlSize(.large)
        .padding(.horizontal, PanelStyle.inset)
        .padding(.vertical, 12)
    }

    private func save() {
        guard canSave else { return }
        let draft = NewTask(
            title: trimmedTitle,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            due: hasDueDate ? selectedDate.map { TaskDate.encode($0, calendar: calendar) } : nil
        )
        Task {
            if await store.add(draft, to: listID) { close() }
        }
    }
}
