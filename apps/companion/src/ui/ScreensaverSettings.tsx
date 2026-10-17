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
						? "On: keeps the Mac awake while an agent runs or waits for you. When the macOS screen saver starts or the screen locks, the Mac locks and a dashboard shows over the lock screen with the display kept on; any input reveals the lock screen."
						: "Off: macOS handles sleep, screen saver and lock as usual."
				}
				htmlFor="screensaver-enabled"
				title="While agents work"
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
