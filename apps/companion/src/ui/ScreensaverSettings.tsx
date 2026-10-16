import {
	SCREENSAVER_IDLE_MINUTES,
	type ScreensaverConfig,
} from "../application/screensaver";

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
		<div className="screensaver-settings">
			<div className="settings-row">
				<label htmlFor="screensaver-enabled">While agents work</label>
				<input
					checked={value.enabled}
					id="screensaver-enabled"
					onChange={(event) =>
						onChange({ ...value, enabled: event.currentTarget.checked })
					}
					type="checkbox"
				/>
			</div>
			<div className="settings-row settings-row-select">
				<label htmlFor="screensaver-idle">Dashboard after</label>
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
			<div className="settings-row">
				<span>Preview</span>
				<button
					aria-label="Preview the dashboard"
					onClick={onPreview}
					type="button"
				>
					Show now
				</button>
			</div>
			<p className="settings-hint">
				{value.enabled
					? `Keeps the Mac awake while an agent runs or waits for you; after ${value.idleMinutes} min without input a dashboard covers every screen, and any input locks the Mac.`
					: "Off: macOS handles sleep, screen saver and lock as usual."}{" "}
				The preview ignores input for two seconds, then any input closes it
				without locking.
			</p>
		</div>
	);
}
