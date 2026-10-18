import type { ReactNode } from "react";
import type { CompanionPreferences } from "../application/preferences";
import {
	COMPANION_FONT_OPTIONS,
	COMPANION_FONT_SIZE_OPTIONS,
	isCompanionFont,
} from "../application/preferences";
import { AgentThemePicker } from "./AgentThemePicker";
import {
	type ClaudeLimitRelayProps,
	ClaudeLimitRelaySettings,
} from "./ClaudeLimitRelaySettings";
import {
	type IdeWindowAccessProps,
	IdeWindowSettings,
} from "./IdeWindowSettings";
import { MenuBarSettings } from "./MenuBarSettings";
import { ScreensaverSettings } from "./ScreensaverSettings";
import {
	SegmentedControl,
	SettingsGroup,
	SettingsPage,
	SettingsRow,
} from "./SettingsLayout";
import type { SettingsCategory } from "./SettingsNav";

/** Every tab except Connections, which the app shell renders itself. */
export type PreferenceCategory = Exclude<SettingsCategory, "connections">;

type Props = {
	readonly category: PreferenceCategory;
	/** Update and connection status, shown first on General. */
	readonly status?: ReactNode;
	readonly claudeLimitRelay: ClaudeLimitRelayProps;
	readonly ideWindowAccess: IdeWindowAccessProps;
	readonly preferences: CompanionPreferences;
	readonly launchAtLogin: boolean;
	readonly launchAtLoginLoading: boolean;
	readonly onLaunchAtLoginChange: (enabled: boolean) => void;
	readonly onPreferencesChange: (preferences: CompanionPreferences) => void;
	readonly onScreensaverPreview: () => void;
};

export function SettingsPanel(props: Props) {
	switch (props.category) {
		case "general":
			return generalPage(props);
		case "menu-bar":
			return (
				<SettingsPage
					category="menu-bar"
					description="The text beside the menu bar icon. Each switch changes the preview at once."
					title="What the menu bar shows"
				>
					<MenuBarSettings
						onChange={(menuBar) =>
							props.onPreferencesChange({ ...props.preferences, menuBar })
						}
						value={props.preferences.menuBar}
					/>
				</SettingsPage>
			);
		case "screen-saver":
			return (
				<SettingsPage
					category="screen-saver"
					description="Keeps the Mac awake while agents work, then covers every screen with the board."
					title="Dashboard while agents work"
				>
					<ScreensaverSettings
						onChange={(screensaver) =>
							props.onPreferencesChange({ ...props.preferences, screensaver })
						}
						onPreview={props.onScreensaverPreview}
						value={props.preferences.screensaver}
					/>
				</SettingsPage>
			);
		case "appearance":
			return appearancePage(props);
	}
}

/** Called, not mounted, so the page's controls stay in the returned tree. */
function generalPage({
	status,
	claudeLimitRelay,
	ideWindowAccess,
	preferences,
	launchAtLogin,
	launchAtLoginLoading,
	onLaunchAtLoginChange,
	onPreferencesChange,
}: Props) {
	return (
		<SettingsPage
			category="general"
			description="What needs attention, when Companion opens, where IDE windows open, and where Claude limits come from."
			title="Status, startup and limits"
		>
			{status}
			<SettingsGroup label="Startup">
				<SettingsRow
					description={
						launchAtLoginLoading
							? "Checking login item state"
							: launchAtLogin
								? "Opens automatically when you sign in"
								: "Opens only when opened manually"
					}
					htmlFor="launch-at-login"
					title="Open at Login"
				>
					<input
						aria-checked={launchAtLogin}
						checked={launchAtLogin}
						className="settings-switch"
						disabled={launchAtLoginLoading}
						id="launch-at-login"
						onChange={(event) =>
							onLaunchAtLoginChange(event.currentTarget.checked)
						}
						role="switch"
						type="checkbox"
					/>
				</SettingsRow>
			</SettingsGroup>
			<IdeWindowSettings
				{...ideWindowAccess}
				onChange={(ideWindow) =>
					onPreferencesChange({ ...preferences, ideWindow })
				}
				value={preferences.ideWindow}
			/>
			<SettingsGroup label="Claude Limits">
				<ClaudeLimitRelaySettings {...claudeLimitRelay} />
			</SettingsGroup>
		</SettingsPage>
	);
}

function appearancePage({ preferences, onPreferencesChange }: Props) {
	const fontOption = COMPANION_FONT_OPTIONS.find(
		(candidate) => candidate.value === preferences.font,
	);
	const fontFamily = fontOption?.cssFamily ?? preferences.font;
	const fontName = fontOption?.label ?? preferences.font;
	const fontSizeOption = COMPANION_FONT_SIZE_OPTIONS.find(
		(candidate) => candidate.value === preferences.fontSize,
	);
	const fontSizeName = fontSizeOption?.label ?? preferences.fontSize;

	return (
		<SettingsPage
			category="appearance"
			description="Applies immediately across Main, Usage, and Settings."
			title="Theme, font and text size"
		>
			<SettingsGroup label="Theme">
				<SettingsRow
					description="Claude Code: warm graphite with a clay accent. Codex: cool neutrals."
					title="Agent theme"
				>
					<AgentThemePicker
						onChange={(theme) => onPreferencesChange({ ...preferences, theme })}
						value={preferences.theme}
					/>
				</SettingsRow>
			</SettingsGroup>
			<SettingsGroup label="Text">
				<SettingsRow
					description="Monospace font for every view."
					htmlFor="companion-font"
					title="Font"
				>
					<div className="settings-select">
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
				</SettingsRow>
				<SettingsRow
					description="Scales every text size in Main, Usage, and Settings."
					stacked
					title="Text Size"
				>
					<SegmentedControl
						label="Text size"
						onChange={(fontSize) =>
							onPreferencesChange({ ...preferences, fontSize })
						}
						options={COMPANION_FONT_SIZE_OPTIONS}
						stretch
						value={preferences.fontSize}
					/>
				</SettingsRow>
				<div className="settings-preview">
					<div className="font-preview" style={{ fontFamily }}>
						<span className="font-preview-label">
							Preview · {fontName} · {fontSizeName}
						</span>
						<code>workbranch feat/update-0619</code>
						<span>1234567890 · RUN 1 · 21/21</span>
						<span className="font-preview-meta">
							ci: build signed macOS DMGs · 11d
						</span>
					</div>
				</div>
			</SettingsGroup>
		</SettingsPage>
	);
}
