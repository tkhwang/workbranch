import SwiftUI
import CompanionCore

enum TerminalTone {
    case accent
    case muted
    case normal
    case warning
    case error
}

struct TerminalPalette: Equatable {
    let background: Color
    let panel: Color
    let text: Color
    let muted: Color
    let accent: Color
    let command: Color
    let warning: Color
    let error: Color
    let rule: Color

    init(theme: CompanionColorTheme) {
        switch theme {
        case .dracula:
            background = Color(red: 0.157, green: 0.165, blue: 0.212)
            panel = Color(red: 0.178, green: 0.188, blue: 0.243)
            text = Color(red: 0.973, green: 0.973, blue: 0.949)
            muted = Color(red: 0.384, green: 0.447, blue: 0.643)
            accent = Color(red: 0.314, green: 0.980, blue: 0.482)
            command = Color(red: 0.545, green: 0.914, blue: 0.992)
            warning = Color(red: 0.945, green: 0.980, blue: 0.549)
            error = Color(red: 1.000, green: 0.333, blue: 0.333)
        case .catppuccin:
            background = Color(red: 0.118, green: 0.118, blue: 0.180)
            panel = Color(red: 0.094, green: 0.094, blue: 0.145)
            text = Color(red: 0.804, green: 0.839, blue: 0.957)
            muted = Color(red: 0.498, green: 0.518, blue: 0.612)
            accent = Color(red: 0.651, green: 0.890, blue: 0.631)
            command = Color(red: 0.537, green: 0.863, blue: 0.922)
            warning = Color(red: 0.976, green: 0.886, blue: 0.686)
            error = Color(red: 0.953, green: 0.545, blue: 0.659)
        case .onedark:
            background = Color(red: 0.157, green: 0.173, blue: 0.204)
            panel = Color(red: 0.129, green: 0.145, blue: 0.169)
            text = Color(red: 0.671, green: 0.698, blue: 0.749)
            muted = Color(red: 0.361, green: 0.388, blue: 0.439)
            accent = Color(red: 0.596, green: 0.765, blue: 0.475)
            command = Color(red: 0.380, green: 0.686, blue: 0.937)
            warning = Color(red: 0.898, green: 0.753, blue: 0.482)
            error = Color(red: 0.878, green: 0.424, blue: 0.459)
        case .nord:
            background = Color(red: 0.180, green: 0.204, blue: 0.251)
            panel = Color(red: 0.229, green: 0.259, blue: 0.322)
            text = Color(red: 0.925, green: 0.937, blue: 0.957)
            muted = Color(red: 0.533, green: 0.604, blue: 0.718)
            accent = Color(red: 0.533, green: 0.753, blue: 0.816)
            command = Color(red: 0.506, green: 0.631, blue: 0.757)
            warning = Color(red: 0.922, green: 0.796, blue: 0.545)
            error = Color(red: 0.749, green: 0.380, blue: 0.416)
        case .tokyonight:
            background = Color(red: 0.102, green: 0.106, blue: 0.149)
            panel = Color(red: 0.086, green: 0.086, blue: 0.118)
            text = Color(red: 0.753, green: 0.792, blue: 0.961)
            muted = Color(red: 0.337, green: 0.373, blue: 0.537)
            accent = Color(red: 0.620, green: 0.808, blue: 0.416)
            command = Color(red: 0.490, green: 0.812, blue: 1.000)
            warning = Color(red: 0.878, green: 0.686, blue: 0.408)
            error = Color(red: 0.969, green: 0.463, blue: 0.557)
        }
        rule = Color.white.opacity(0.10)
    }

    func color(for tone: TerminalTone) -> Color {
        switch tone {
        case .accent: return accent
        case .muted: return muted
        case .normal: return text
        case .warning: return warning
        case .error: return error
        }
    }
}

private struct TerminalPaletteKey: EnvironmentKey {
    static let defaultValue = TerminalPalette(theme: .default)
}

extension EnvironmentValues {
    var terminalPalette: TerminalPalette {
        get { self[TerminalPaletteKey.self] }
        set { self[TerminalPaletteKey.self] = newValue }
    }
}

struct TerminalLine: View {
    let prefix: String
    let command: String
    let tone: TerminalTone
    @Environment(\.terminalPalette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(prefix)
                .foregroundStyle(palette.accent)
            Text(command)
                .foregroundStyle(palette.color(for: tone))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

struct TerminalToken: View {
    let label: String
    let value: String
    let tone: TerminalTone
    @Environment(\.terminalPalette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            Text("\(label)=")
                .foregroundStyle(palette.muted)
            Text(value)
                .foregroundStyle(palette.color(for: tone))
        }
    }
}
