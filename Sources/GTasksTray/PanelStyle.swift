import SwiftUI

enum PanelStyle {
    static let width: CGFloat = 420
    static let height: CGFloat = 550
    static let inset: CGFloat = 18
}

struct AddTaskButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .buttonStyle(AddTaskButtonStyle())
    }
}

private struct AddTaskButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .padding(.horizontal, 13)
            .frame(minHeight: 33)
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .contentShape(Capsule())

        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            label.glassEffect(
                .regular.tint(isEnabled ? Color.accentColor.opacity(0.24) : nil).interactive(isEnabled),
                in: .capsule
            )
        } else {
            classic(label, pressed: configuration.isPressed)
        }
        #else
        classic(label, pressed: configuration.isPressed)
        #endif
    }

    private func classic(_ label: some View, pressed: Bool) -> some View {
        label
            .background(Color.accentColor.opacity(isEnabled ? (pressed ? 0.28 : 0.16) : 0.05), in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.accentColor.opacity(isEnabled ? 0.24 : 0.08))
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    @ViewBuilder
    func panelButton(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
                    .tint(Color.accentColor)
                    .buttonBorderShape(.capsule)
            } else {
                buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
            }
        } else {
            classicPanelButton(prominent: prominent)
        }
        #else
        classicPanelButton(prominent: prominent)
        #endif
    }

    @ViewBuilder
    private func classicPanelButton(prominent: Bool) -> some View {
        if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }

    func panelCard(radius: CGFloat = 15) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        return background(Color(nsColor: .controlBackgroundColor).opacity(0.68), in: shape)
            .overlay {
                shape.strokeBorder(.primary.opacity(0.085))
                    .allowsHitTesting(false)
            }
    }
}
