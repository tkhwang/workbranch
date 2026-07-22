import type { CompanionPreferences } from "../application/preferences";
import {
	COMPANION_FONT_OPTIONS,
	isCompanionFont,
} from "../application/preferences";
import { AgentThemePicker } from "./AgentThemePicker";
import { TerminalPanel } from "./TerminalPanel";

type Props = {
	readonly preferences: CompanionPreferences;
	readonly launchAtLogin: boolean;
	readonly launchAtLoginLoading: boolean;
	readonly onLaunchAtLoginChange: (enabled: boolean) => void;
	readonly onPreferencesChange: (preferences: CompanionPreferences) => void;
};

export function SettingsPanel({
	preferences,
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

	return (
		<section className="settings-panel" aria-label="Settings">
			<div className="settings-panel-header">
				<div>
					<h2>Settings</h2>
					<p>Companion preferences</p>
				</div>
			</div>
			<TerminalPanel theme={preferences.theme} label="Startup">
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
			</TerminalPanel>
			<TerminalPanel theme={preferences.theme} label="Font">
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
			</TerminalPanel>
			<TerminalPanel theme={preferences.theme} label="Theme">
				<AgentThemePicker
					value={preferences.theme}
					onChange={(theme) => onPreferencesChange({ ...preferences, theme })}
				/>
				<p className="settings-hint">
					Applies immediately across Main, Activity, and Settings.
				</p>
			</TerminalPanel>
		</section>
	);
}
