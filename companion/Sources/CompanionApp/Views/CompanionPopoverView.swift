import SwiftUI
import CompanionCore

struct CompanionPopoverView: View {
    @ObservedObject var store: StateStore
    @State private var showingSettings = false
    @State private var draftFontName = ""
    @State private var draftFontSize = CompanionFontSettings.default.size
    @State private var draftColorTheme = CompanionColorTheme.default

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if showingSettings {
                settingsPanel
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(store.menuState.sections) { section in
                        sectionView(section)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
                .overlay(palette.rule)
            footer
        }
        .font(terminalFont)
        .foregroundStyle(palette.text)
        .padding(14)
        .frame(width: 560, height: 720)
        .background(palette.background)
        .environment(\.terminalPalette, palette)
    }

    private var terminalFont: Font {
        .custom(store.fontSettings.name, size: CGFloat(store.fontSettings.size))
    }

    private var palette: TerminalPalette {
        TerminalPalette(theme: store.colorTheme)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("workbranch-companion")
                .fontWeight(.bold)
                .foregroundStyle(palette.accent)
            Spacer()
        }
    }

    private func sectionView(_ section: MenuSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TerminalLine(prefix: "[*]", command: section.title, tone: .accent)
            ForEach(section.rows) { row in
                RowView(row: row, store: store)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(palette.rule, lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.accent)
            .help("Companion settings")
            if !store.statusMessage.isEmpty {
                TerminalLine(prefix: "#", command: store.statusMessage, tone: .muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            IconControl(systemName: "arrow.clockwise", help: "Refresh now", tone: palette.accent) {
                store.refreshAll()
            }
            IconControl(systemName: "power", help: "Quit", tone: palette.warning) {
                store.quit()
            }
        }
    }

    private var settingsPanel: some View {
        AppearanceSettingsView(
            fontName: $draftFontName,
            fontSize: $draftFontSize,
            colorTheme: $draftColorTheme,
            onOpenConfig: store.openConfig,
            onCancel: { showingSettings = false },
            onSave: saveSettings,
            onThemeChange: applyTheme
        )
        .environment(\.terminalPalette, palette)
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(palette.rule, lineWidth: 1)
        )
    }

    private func openSettings() {
        draftFontName = store.fontSettings.name
        draftFontSize = store.fontSettings.size
        draftColorTheme = store.colorTheme
        showingSettings = true
    }

    private func saveSettings() {
        if store.saveAppearance(
            fontName: draftFontName,
            fontSize: draftFontSize,
            colorTheme: draftColorTheme
        ) {
            showingSettings = false
        }
    }

    private func applyTheme(_ theme: CompanionColorTheme) {
        draftColorTheme = theme
    }
}

private struct IconControl: View {
    let systemName: String
    let help: String
    let tone: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tone)
        .help(help)
    }
}
