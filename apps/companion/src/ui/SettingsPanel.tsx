import type {
	CompanionPreferences,
	CompanionResolvedThemeMode,
} from "../application/preferences";
import {
	COMPANION_FONT_OPTIONS,
	COMPANION_THEME_MODE_OPTIONS,
	COMPANION_THEME_OPTIONS,
	isCompanionFont,
	resolvedCompanionTheme,
} from "../application/preferences";

type Props = {
	readonly preferences: CompanionPreferences;
	readonly systemThemeMode: CompanionResolvedThemeMode;
	readonly launchAtLogin: boolean;
	readonly launchAtLoginLoading: boolean;
	readonly onLaunchAtLoginChange: (enabled: boolean) => void;
	readonly onPreferencesChange: (preferences: CompanionPreferences) => void;
};

const THEME_SWATCH_CHIPS = [
	"surface",
	"accent",
	"secondary",
	"success",
] as const;

export function SettingsPanel({
	preferences,
	systemThemeMode,
	launchAtLogin,
	launchAtLoginLoading,
	onLaunchAtLoginChange,
	onPreferencesChange,
}: Props) {
	const fontOption = COMPANION_FONT_OPTIONS.find(
		(candidate) => candidate.value === preferences.font,
	);
	const fontFamily = fontOption?.cssFamily ?? preferences.font;
	const fontName = fontOption?.label ?? preferences.font;
	const activeTheme = resolvedCompanionTheme(preferences, systemThemeMode);
	const themeOption = COMPANION_THEME_OPTIONS.find(
		(candidate) => candidate.value === activeTheme,
	);
	const themeName = themeOption?.label ?? activeTheme;
	const resolvedThemeMode =
		preferences.themeMode === "system"
			? systemThemeMode
			: preferences.themeMode;
	const visibleThemeOptions = COMPANION_THEME_OPTIONS.filter(
		(option) => option.mode === resolvedThemeMode,
	);
	const modeHint =
		preferences.themeMode === "system"
			? `System (${systemThemeMode === "dark" ? "Dark" : "Light"} now)`
			: `${preferences.themeMode === "dark" ? "Dark" : "Light"} mode`;

	return (
		<section className="settings-panel" aria-label="Settings">
			<div className="settings-panel-header">
				<div>
					<h2>Settings</h2>
					<p>Companion preferences</p>
				</div>
			</div>
			<fieldset className="settings-section">
				<legend>Startup</legend>
				<div className="settings-row">
					<label htmlFor="launch-at-login">Launch at login</label>
					<input
						checked={launchAtLogin}
						disabled={launchAtLoginLoading}
						id="launch-at-login"
						onChange={(event) =>
							onLaunchAtLoginChange(event.currentTarget.checked)
						}
						type="checkbox"
					/>
				</div>
				<p className="settings-hint">
					{launchAtLoginLoading
						? "Checking login item state"
						: launchAtLogin
							? "Launches automatically when you sign in"
							: "Launches only when opened manually"}
				</p>
			</fieldset>
			<fieldset className="settings-section">
				<legend>Font</legend>
				<div className="settings-row settings-row-select">
					<label htmlFor="companion-font">Font</label>
					<select
						id="companion-font"
						onChange={(event) => {
							const nextFont = event.currentTarget.value;
							if (isCompanionFont(nextFont)) {
								onPreferencesChange({ ...preferences, font: nextFont });
							}
						}}
						value={preferences.font}
					>
						{COMPANION_FONT_OPTIONS.map((option) => (
							<option key={option.value} value={option.value}>
								{option.label}
							</option>
						))}
					</select>
				</div>
				<div className="font-preview" style={{ fontFamily }}>
					<span className="font-preview-label">Preview · {fontName}</span>
					<code>workbranch feat/update-0619</code>
					<span>1234567890 · RUN 1 · 21/21</span>
				</div>
				<p className="settings-hint">Current font: {fontName}</p>
			</fieldset>
			<fieldset className="settings-section">
				<legend>Theme</legend>
				<div className="theme-mode-toggle">
					{COMPANION_THEME_MODE_OPTIONS.map((option) => {
						const selected = option.value === preferences.themeMode;
						return (
							<button
								aria-label={`Use ${option.label} theme mode`}
								aria-pressed={selected}
								className="theme-mode-button"
								data-active={selected ? "true" : "false"}
								key={option.value}
								onClick={() =>
									onPreferencesChange({
										...preferences,
										themeMode: option.value,
									})
								}
								type="button"
							>
								{option.label}
							</button>
						);
					})}
				</div>
				<div className="theme-button-grid">
					{visibleThemeOptions.map((option) => {
						const selected = option.family === preferences.themeFamily;
						return (
							<button
								aria-label={`Use ${option.familyLabel} theme`}
								aria-pressed={selected}
								className="theme-button"
								data-active={selected ? "true" : "false"}
								key={option.family}
								onClick={() =>
									onPreferencesChange({
										...preferences,
										themeFamily: option.family,
									})
								}
								type="button"
							>
								<span
									aria-hidden="true"
									className={`theme-swatch theme-swatch-${option.value}`}
								>
									{THEME_SWATCH_CHIPS.map((chip) => (
										<span className="theme-swatch-color" key={chip} />
									))}
								</span>
								<span className="theme-button-label">{option.familyLabel}</span>
							</button>
						);
					})}
				</div>
				<p className="settings-hint">
					{modeHint} · Current theme: {themeName}
				</p>
			</fieldset>
		</section>
	);
}
