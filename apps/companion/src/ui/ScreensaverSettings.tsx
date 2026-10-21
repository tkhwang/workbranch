import type { ScreensaverConfig } from "../application/screensaver";
import { SettingsGroup, SettingsRow } from "./SettingsLayout";

type ScreensaverSettingsProps = {
	readonly value: ScreensaverConfig;
	readonly onChange: (config: ScreensaverConfig) => void;
	/** Shows the dashboard now; works while the feature is off, too. */
	readonly onPreview: () => void;
};

/** One switch for the whole feature; macOS decides when the dashboard shows. */
export function ScreensaverSettings({
	value,
	onChange,
	onPreview,
}: ScreensaverSettingsProps) {
	return (
		<SettingsGroup label="Screen Saver">
			<SettingsRow
				description={
					value.enabled
						? "On: keeps the Mac awake while an agent runs or waits for you. When the macOS screen saver starts or the screen locks, the Mac locks and a dashboard shows over the lock screen with the display kept on, while agents work and for up to 30 minutes after they stop; any input reveals the lock screen. Where macOS cannot lock, input just closes the dashboard."
						: "Off: macOS handles sleep, screen saver and lock as usual."
				}
				htmlFor="screensaver-enabled"
				title="Cover the lock screen"
			>
				<input
					aria-checked={value.enabled}
					checked={value.enabled}
					className="settings-switch"
					id="screensaver-enabled"
					onChange={(event) =>
						onChange({ ...value, enabled: event.currentTarget.checked })
					}
					role="switch"
					type="checkbox"
				/>
			</SettingsRow>
			<SettingsRow
				description={
					value.showMessages
						? "On: each task on the dashboard lists its last three requests, replies and commits. Anyone at the desk can read them while the dashboard covers the lock screen."
						: "Off: the dashboard shows branch and repo names, states and times only, since anyone at the desk can read it."
				}
				htmlFor="screensaver-show-messages"
				title="Show recent messages"
			>
				<input
					aria-checked={value.showMessages}
					checked={value.showMessages}
					className="settings-switch"
					id="screensaver-show-messages"
					onChange={(event) =>
						onChange({ ...value, showMessages: event.currentTarget.checked })
					}
					role="switch"
					type="checkbox"
				/>
			</SettingsRow>
			<SettingsRow
				description="Works while the switch is off, too. The preview ignores input for two seconds, then any input closes it without locking."
				title="Preview"
			>
				<button
					aria-label="Preview the dashboard"
					onClick={onPreview}
					type="button"
				>
					Show now
				</button>
			</SettingsRow>
		</SettingsGroup>
	);
}
