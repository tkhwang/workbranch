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
        case .matrix:
            background = Color(red: 0.035, green: 0.039, blue: 0.055)
            panel = Color(red: 0.055, green: 0.059, blue: 0.078)
            text = Color(red: 0.84, green: 0.88, blue: 0.82)
            muted = Color(red: 0.49, green: 0.54, blue: 0.53)
            accent = Color(red: 0.45, green: 0.95, blue: 0.57)
            command = Color(red: 0.72, green: 0.86, blue: 1.0)
            warning = Color(red: 0.96, green: 0.76, blue: 0.38)
            error = Color(red: 1.0, green: 0.43, blue: 0.43)
        case .amber:
            background = Color(red: 0.055, green: 0.039, blue: 0.020)
            panel = Color(red: 0.082, green: 0.059, blue: 0.031)
            text = Color(red: 0.94, green: 0.82, blue: 0.58)
            muted = Color(red: 0.58, green: 0.47, blue: 0.31)
            accent = Color(red: 1.0, green: 0.72, blue: 0.30)
            command = Color(red: 1.0, green: 0.88, blue: 0.58)
            warning = Color(red: 1.0, green: 0.52, blue: 0.22)
            error = Color(red: 1.0, green: 0.33, blue: 0.22)
        case .nord:
            background = Color(red: 0.180, green: 0.204, blue: 0.251)
            panel = Color(red: 0.229, green: 0.259, blue: 0.322)
            text = Color(red: 0.925, green: 0.937, blue: 0.957)
            muted = Color(red: 0.533, green: 0.604, blue: 0.718)
            accent = Color(red: 0.533, green: 0.753, blue: 0.816)
            command = Color(red: 0.506, green: 0.631, blue: 0.757)
            warning = Color(red: 0.922, green: 0.796, blue: 0.545)
            error = Color(red: 0.749, green: 0.380, blue: 0.416)
        case .solarized:
            background = Color(red: 0.000, green: 0.169, blue: 0.212)
            panel = Color(red: 0.027, green: 0.212, blue: 0.259)
            text = Color(red: 0.576, green: 0.631, blue: 0.631)
            muted = Color(red: 0.396, green: 0.482, blue: 0.514)
            accent = Color(red: 0.522, green: 0.600, blue: 0.000)
            command = Color(red: 0.149, green: 0.545, blue: 0.824)
            warning = Color(red: 0.710, green: 0.537, blue: 0.000)
            error = Color(red: 0.863, green: 0.196, blue: 0.184)
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
