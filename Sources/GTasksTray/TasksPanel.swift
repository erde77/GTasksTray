import SwiftUI

struct TasksPanel: View {
    private static let recentCompletedCount = 5

    @ObservedObject var store: TaskStore
    let chooseClient: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("completionSoundEnabled") private var completionSoundEnabled = true
    @State private var adding = false
    @State private var completedLimit = Self.recentCompletedCount
    @State private var chromeHovered = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = store.error {
                errorBanner(error)
            }
            Group {
                if store.connection != .connected {
                    connectionView
                } else if adding {
                    NewTaskForm(store: store) { adding = false }
                } else if store.hasLoaded {
                    tasksView
                } else if store.isRefreshing {
                    ProgressView("Pobieranie zadań…")
                        .controlSize(.small)
                } else {
                    placeholder("arrow.clockwise", title: "Zadania czekają na synchronizację") {
                        Button("Odśwież zadania") { Task { await store.refresh(force: true) } }
                            .panelButton(prominent: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !adding {
                Divider()
                footer
            }
        }
        .frame(width: PanelStyle.width, height: PanelStyle.height)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: adding)
        .environment(\.locale, Locale(identifier: "pl_PL"))
        .onChange(of: store.connection) { _ in
            adding = false
            completedLimit = Self.recentCompletedCount
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            if adding {
                Button {
                    adding = false
                } label: {
                    Image(systemName: "chevron.left").frame(width: 14, height: 14)
                }
                .panelButton()
                .disabled(store.isSaving)
                .help("Wróć do zadań")
                .accessibilityLabel("Wróć do zadań")
            } else {
                Image(systemName: "checklist")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 35, height: 35)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
            }

            Text(adding ? "Nowe zadanie" : "Google Tasks")
                .font(.system(size: 17, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 5)
            if !adding {
                if store.connection == .connected {
                    taskActions
                }
                options
            }
        }
        .controlSize(.large)
        .padding(.horizontal, PanelStyle.inset)
        .frame(height: 66)
    }

    private var taskActions: some View {
        HStack(spacing: 8) {
            Button {
                Task { await store.refresh(force: true) }
            } label: {
                Group {
                    if store.isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .frame(width: 15, height: 15)
            }
            .panelButton()
            .disabled(store.isBusy)
            .keyboardShortcut("r", modifiers: .command)
            .help("Odśwież zadania (⌘R)")
            .accessibilityLabel(store.isRefreshing ? "Odświeżanie zadań" : "Odśwież zadania")

            AddTaskButton("Dodaj") {
                adding = true
            }
            .disabled(store.groups.isEmpty)
            .keyboardShortcut("n", modifiers: .command)
            .help("Dodaj zadanie (⌘N)")
        }
    }

    private var options: some View {
        Menu {
            if store.connection == .signedOut {
                Button("Zmień plik klienta OAuth…", action: chooseClient)
                    .disabled(store.isBusy)
            }
            if store.connection == .connected {
                Button("Wyloguj") { store.signOut() }
                    .disabled(store.isBusy)
            }
            Toggle("Dźwięk ukończenia", isOn: $completionSoundEnabled)
            Divider()
            Button("Zakończ GTasksTray") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 22, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Opcje aplikacji")
        .accessibilityLabel("Opcje aplikacji")
    }

    private var connectionView: some View {
        placeholder("person.crop.circle", title: "Połącz konto Google") {
            if store.connection == .unconfigured {
                Text("Wybierz plik klienta OAuth z Google Cloud, aby połączyć aplikację z Google Tasks.")
                    .foregroundStyle(.secondary)
                Button("Wybierz plik OAuth…", action: chooseClient)
                    .panelButton(prominent: true)
                Link(
                    "Jak skonfigurować klienta OAuth?",
                    destination: URL(string: "https://developers.google.com/identity/protocols/oauth2/native-app#creatingcred")!
                )
                .font(.caption)
            } else if store.isSigningIn {
                ProgressView("Dokończ logowanie w przeglądarce…")
                    .controlSize(.small)
                Button("Anuluj logowanie") { store.cancelSignIn() }
            } else {
                Text("Zaloguj się, aby wyświetlać i dodawać zadania bezpośrednio z paska menu.")
                    .foregroundStyle(.secondary)
                Button("Zaloguj się przez Google") { store.signIn() }
                    .panelButton(prominent: true)
            }
        }
    }

    private var tasksView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    Text("Do zrobienia")
                        .font(.system(size: 23, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(store.openCount, format: .number)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.primary.opacity(0.065), in: Capsule())
                }
                .accessibilityElement(children: .combine)

                if store.openCount == 0 {
                    Label("Wszystko zrobione", systemImage: "checkmark.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                        .panelCard()
                }
                ForEach(store.openGroups) { group in
                    openList(group)
                }

                if !store.completedTasks.isEmpty {
                    Label("Ukończone", systemImage: "checkmark.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 8)
                    ForEach(store.completedTasks.prefix(completedLimit)) { entry in
                        taskRow(entry.task, in: entry.list, completedAt: entry.completedAt)
                            .panelCard(radius: 13)
                    }
                    HStack(spacing: 8) {
                        if store.completedTasks.count > completedLimit {
                            Button {
                                completedLimit += 20
                            } label: {
                                Label("Pokaż więcej", systemImage: "chevron.down")
                            }
                            .panelButton()
                        }
                        if completedLimit > Self.recentCompletedCount {
                            Button("Pokaż mniej") { completedLimit = Self.recentCompletedCount }
                                .panelButton()
                        }
                    }
                }
            }
            .padding(PanelStyle.inset)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: store.openCount)
        }
    }

    private func openList(_ group: TaskGroup) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(group.list.title, systemImage: "tray")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(group.tasks) { task in
                    if task.id != group.tasks.first?.id { Divider().padding(.horizontal, 12) }
                    taskRow(task, in: group.list)
                }
            }
            .panelCard()
        }
        .transition(.opacity)
    }

    private func taskRow(_ task: GoogleTask, in list: GoogleTaskList, completedAt: Date? = nil) -> some View {
        let location = TaskLocation(listID: list.id, taskID: task.id)
        let confirmed = store.completion == .confirmed(location)
        return HStack(alignment: .top, spacing: 9) {
            if task.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 20)
                    .accessibilityLabel("Ukończone")
            } else if confirmed {
                CompletionMark(tint: .accentColor)
            } else if store.completion == .saving(location) {
                ProgressView().controlSize(.mini).frame(width: 22, height: 20)
            } else {
                Button {
                    Task { await store.complete(task, in: list.id, playSound: completionSoundEnabled) }
                } label: {
                    Image(systemName: "circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.isBusy)
                .help("Oznacz jako ukończone")
                .accessibilityLabel("Ukończ zadanie: \(task.displayTitle)")
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(task.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .strikethrough(task.isCompleted || confirmed)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                if task.isCompleted {
                    Label(list.title, systemImage: "list.bullet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let due = task.due.flatMap(TaskDate.scheduledDay) {
                    Label("Zaplanowano: \(due)", systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let completedAt {
                    Label {
                        Text("Ukończono: \(completedAt, format: .dateTime.day().month(.abbreviated).year())")
                    } icon: {
                        Image(systemName: "checkmark")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                let links = task.sourceLinks
                ForEach(links.indices, id: \.self) { index in
                    let source = links[index]
                    if let url = URL(string: source.link), let scheme = url.scheme?.lowercased(),
                       ["http", "https"].contains(scheme), url.host != nil {
                        Button {
                            Task { await store.openInChrome(url) }
                        } label: {
                            let description = source.description ?? ""
                            Label(description.isEmpty ? "Otwórz źródło" : description, systemImage: "link")
                                .font(.caption)
                        }
                        .buttonStyle(.link)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 11)
        .padding(.trailing, 13)
        .padding(.leading, task.isCompleted || task.parent == nil ? 10 : 24)
        .background(confirmed ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 14))
        .transition(.opacity)
    }

    private func placeholder<Content: View>(
        _ icon: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 54, height: 54)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)
            Text(title).font(.system(size: 16, weight: .semibold))
            content()
        }
        .font(.system(size: 13))
        .multilineTextAlignment(.center)
        .frame(maxWidth: 265)
        .padding()
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            Text(message).frame(maxWidth: .infinity, alignment: .leading)
            Button {
                store.dismissError()
            } label: {
                Image(systemName: "xmark").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zamknij komunikat")
        }
        .font(.caption)
        .padding(9)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, PanelStyle.inset)
        .padding(.top, 10)
    }

    private var footer: some View {
        Button {
            Task { await store.openTasksInChrome() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                Text("Otwórz w Chrome")
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.primary.opacity(chromeHovered ? 0.085 : 0.035), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { chromeHovered = $0 }
        .accessibilityLabel("Otwórz Google Tasks w Chrome")
        .padding(.horizontal, PanelStyle.inset)
        .padding(.vertical, 9)
    }
}

private struct CompletionMark: View {
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .strokeBorder(tint, lineWidth: 1.5)
                    .scaleEffect(expanded ? 1.8 : 0.7)
                    .opacity(expanded ? 0 : 0.8)
                    .animation(.easeOut(duration: 0.4), value: expanded)
            }
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(tint)
                .scaleEffect(expanded || reduceMotion ? 1 : 0.55)
                .animation(reduceMotion ? nil : .spring(response: 0.27, dampingFraction: 0.45), value: expanded)
        }
        .frame(width: 22, height: 20)
        .accessibilityLabel("Ukończone")
        .onAppear { expanded = true }
    }
}
