import {
	SCREENSAVER_IDLE_MINUTES,
	type ScreensaverConfig,
} from "../application/screensaver";
import { SettingsGroup, SettingsRow } from "./SettingsLayout";

type ScreensaverSettingsProps = {
	readonly value: ScreensaverConfig;
	readonly onChange: (config: ScreensaverConfig) => void;
	/** Shows the dashboard now; works while the feature is off, too. */
	readonly onPreview: () => void;
};

const IDLE_MINUTE_CHOICES = Array.from(
	{ length: SCREENSAVER_IDLE_MINUTES.max - SCREENSAVER_IDLE_MINUTES.min + 1 },
	(_, index) => SCREENSAVER_IDLE_MINUTES.min + index,
);

/** One switch for the whole feature, plus how long input may pause. */
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
						? `On: keeps the Mac awake while an agent runs or waits for you; after ${value.idleMinutes} min without input a dashboard covers every screen, and any input locks the Mac.`
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
				description="Minutes without input before the dashboard covers every screen."
				htmlFor="screensaver-idle"
				title="Dashboard after"
			>
				<div className="settings-select">
					<select
						disabled={!value.enabled}
						id="screensaver-idle"
						onChange={(event) =>
							onChange({
								...value,
								idleMinutes: Number(event.currentTarget.value),
							})
						}
						value={String(value.idleMinutes)}
					>
						{IDLE_MINUTE_CHOICES.map((minutes) => (
							<option key={minutes} value={String(minutes)}>
								{minutes} min
							</option>
						))}
					</select>
				</div>
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
