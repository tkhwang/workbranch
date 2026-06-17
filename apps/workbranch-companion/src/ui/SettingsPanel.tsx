import type {
	CompanionFont,
	CompanionPreferences,
	CompanionTheme,
} from "../application/preferences";
import {
	COMPANION_FONT_OPTIONS,
	COMPANION_THEME_OPTIONS,
	isCompanionFont,
	isCompanionTheme,
} from "../application/preferences";

type Props = {
	readonly preferences: CompanionPreferences;
	readonly launchAtLogin: boolean;
	readonly launchAtLoginLoading: boolean;
	readonly onLaunchAtLoginChange: (enabled: boolean) => void;
	readonly onPreferencesChange: (preferences: CompanionPreferences) => void;
};

function fontLabel(font: CompanionFont): string {
	const option = COMPANION_FONT_OPTIONS.find(
		(candidate) => candidate.value === font,
	);
	return option?.label ?? font;
}

function themeLabel(theme: CompanionTheme): string {
	const option = COMPANION_THEME_OPTIONS.find(
		(candidate) => candidate.value === theme,
	);
	return option?.label ?? theme;
}

export function SettingsPanel({
	preferences,
	launchAtLogin,
	launchAtLoginLoading,
	onLaunchAtLoginChange,
	onPreferencesChange,
}: Props) {
	return (
		<section className="settings-panel" aria-label="Settings">
			<div className="settings-panel-header">
				<div>
					<h2>Setting</h2>
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
				<p className="settings-hint">
					Current font: {fontLabel(preferences.font)}
				</p>
			</fieldset>
			<fieldset className="settings-section">
				<legend>Theme</legend>
				<div className="settings-row settings-row-select">
					<label htmlFor="companion-theme">Theme</label>
					<select
						id="companion-theme"
						onChange={(event) => {
							const nextTheme = event.currentTarget.value;
							if (isCompanionTheme(nextTheme)) {
								onPreferencesChange({ ...preferences, theme: nextTheme });
							}
						}}
						value={preferences.theme}
					>
						{COMPANION_THEME_OPTIONS.map((option) => (
							<option key={option.value} value={option.value}>
								{option.label}
							</option>
						))}
					</select>
				</div>
				<div className="theme-preview-list" aria-hidden="true">
					{COMPANION_THEME_OPTIONS.map((option) => (
						<span
							className={`theme-preview theme-preview-${option.value}`}
							key={option.value}
						/>
					))}
				</div>
				<p className="settings-hint">
					Current theme: {themeLabel(preferences.theme)}
				</p>
			</fieldset>
		</section>
	);
}
