import AppKit
import SwiftUI
import CompanionCore

struct AppearanceSettingsView: View {
    @Binding var fontName: String
    @Binding var fontSize: Double
    @Binding var colorTheme: CompanionColorTheme
    let onOpenConfig: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void
    let onThemeChange: (CompanionColorTheme) -> Void
    @Environment(\.terminalPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            fontSection
            themeSection
            preview
            footer
        }
        .padding(18)
        .frame(width: 380)
    }

    private var header: some View {
        HStack {
            Text("Companion Settings")
                .font(.headline)
            Spacer()
            Button(action: onOpenConfig) {
                Image(systemName: "doc.text")
            }
            .help("Open config file")
        }
    }

    private var fontSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fixed-width font")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Fixed-width font", selection: $fontName) {
                ForEach(FixedWidthFontCatalog.names(including: fontName), id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Stepper(value: $fontSize, in: 9...24, step: 0.5) {
                Text("Size \(fontSize, specifier: "%.1f")")
                    .monospacedDigit()
            }
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color theme")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(CompanionColorTheme.allCases, id: \.self) { theme in
                    ThemeTile(theme: theme, isSelected: colorTheme == theme) {
                        colorTheme = theme
                        onThemeChange(theme)
                    }
                }
            }
        }
    }

    private var preview: some View {
        let previewPalette = TerminalPalette(theme: colorTheme)
        return VStack(alignment: .leading, spacing: 4) {
            Text("$ feat-update-0613 status=done progress=5/5")
                .foregroundStyle(previewPalette.accent)
            Text("# /Users/tommyhwang/Documents/git-tkhwang/workbranch")
                .foregroundStyle(previewPalette.muted)
        }
        .font(.custom(fontName, size: CGFloat(fontSize)))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(previewPalette.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(previewPalette.rule, lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
            Button("Save", action: onSave)
                .keyboardShortcut(.defaultAction)
                .disabled(fontName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

private struct ThemeTile: View {
    let theme: CompanionColorTheme
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        let palette = TerminalPalette(theme: theme)
        return Button(action: select) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Circle().fill(palette.accent).frame(width: 8, height: 8)
                    Circle().fill(palette.command).frame(width: 8, height: 8)
                    Circle().fill(palette.warning).frame(width: 8, height: 8)
                    Spacer()
                    if isSelected { Image(systemName: "checkmark") }
                }
                Text(theme.label)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(palette.text)
            .background(palette.panel, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? palette.accent : palette.rule, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private enum FixedWidthFontCatalog {
    static func names(including selected: String) -> [String] {
        var names = Set(systemNames)
        let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { names.insert(trimmed) }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static var systemNames: [String] {
        NSFontManager.shared.availableFontFamilies.compactMap { family in
            let font = NSFontManager.shared.font(
                withFamily: family,
                traits: .fixedPitchFontMask,
                weight: 5,
                size: CompanionFontSettings.default.size
            )
            return font == nil ? nil : family
        }
    }
}
