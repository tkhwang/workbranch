import type {
	CompanionPreferences,
	CompanionResolvedThemeMode,
} from "../application/preferences";
import {
	COMPANION_FONT_OPTIONS,
	COMPANION_THEME_MODE_OPTIONS,
	isCompanionFont,
} from "../application/preferences";

type Props = {
	readonly preferences: CompanionPreferences;
	readonly systemThemeMode: CompanionResolvedThemeMode;
	readonly launchAtLogin: boolean;
	readonly launchAtLoginLoading: boolean;
	readonly onLaunchAtLoginChange: (enabled: boolean) => void;
	readonly onPreferencesChange: (preferences: CompanionPreferences) => void;
};

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
					<label htmlFor="launch-at-login">Open at Login</label>
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
							? "Opens automatically when you sign in"
							: "Opens only when opened manually"}
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
										themeFamily: "companion",
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
				<p className="settings-hint">
					{modeHint} · Palette: Catppuccin Dark / White Light
				</p>
			</fieldset>
		</section>
	);
}
