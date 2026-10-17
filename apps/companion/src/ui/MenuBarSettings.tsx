import {
	isIconOnly,
	MENU_BAR_ITEM_OPTIONS,
	MENU_BAR_PERCENT_OPTIONS,
	type MenuBarConfig,
	menuBarSampleTitle,
} from "../application/menuBar";
import { SegmentedControl, SettingsGroup, SettingsRow } from "./SettingsLayout";

type MenuBarSettingsProps = {
	readonly value: MenuBarConfig;
	readonly onChange: (config: MenuBarConfig) => void;
};

const PERCENT_SEGMENTS = MENU_BAR_PERCENT_OPTIONS.map((option) => ({
	value: option.value,
	label: option.label,
	ariaLabel: `Show limits as ${option.label}`,
}));

/** Same outline as src-tauri/icons/tray-template.svg. */
function TrayGhost() {
	return (
		<svg aria-hidden="true" className="menu-bar-ghost" viewBox="0 0 18 18">
			<path
				d="M3.5 8.2A5.5 5.5 0 0 1 14.5 8.2V15.6Q13.6 14.3 12.67 15.6Q11.75 16.9 10.83 15.6Q9.92 14.3 9 15.6Q8.08 16.9 7.17 15.6Q6.25 14.3 5.33 15.6Q4.42 16.9 3.5 15.6Z"
				fill="none"
				stroke="currentColor"
				strokeLinejoin="round"
				strokeWidth="1.35"
			/>
			<circle cx="7" cy="8.4" fill="currentColor" r="1.05" />
			<circle cx="11" cy="8.4" fill="currentColor" r="1.05" />
		</svg>
	);
}

/**
 * Builds the tray title from items. The preview shows what the picked items
 * produce with sample numbers, so each switch's effect is visible at once.
 */
export function MenuBarSettings({ value, onChange }: MenuBarSettingsProps) {
	const title = menuBarSampleTitle(value);
	const percentDisabled =
		!value.claude5h && !value.claudeWeekly && !value.codexWeekly;
	return (
		<>
			<SettingsGroup label="Preview">
				<div className="settings-preview">
					<span className="menu-bar-sample" data-testid="menu-bar-preview">
						<TrayGhost />
						{title === "" ? null : (
							<span className="menu-bar-sample-text">{title}</span>
						)}
					</span>
					<p className="settings-preview-hint">
						{isIconOnly(value)
							? "Nothing picked: the menu bar shows the icon alone."
							: "Sample numbers. The menu bar updates every minute; a limit reading too old to trust shows as –."}
					</p>
				</div>
			</SettingsGroup>
			<SettingsGroup ariaLabel="Menu bar items" label="Items">
				{MENU_BAR_ITEM_OPTIONS.map((option) => {
					const id = `menu-bar-${option.item}`;
					return (
						<SettingsRow
							description={option.detail}
							htmlFor={id}
							key={option.item}
							title={option.label}
						>
							<input
								aria-checked={value[option.item]}
								aria-label={`Show ${option.label} in the menu bar`}
								checked={value[option.item]}
								className="settings-switch"
								id={id}
								onChange={(event) =>
									onChange({
										...value,
										[option.item]: event.currentTarget.checked,
									})
								}
								role="switch"
								type="checkbox"
							/>
						</SettingsRow>
					);
				})}
			</SettingsGroup>
			<SettingsGroup label="Limits">
				<SettingsRow
					description="Used counts up toward the limit; Remaining counts down."
					title="Show limits as"
				>
					<SegmentedControl
						disabled={percentDisabled}
						label="Limit percent"
						onChange={(percent) => onChange({ ...value, percent })}
						options={PERCENT_SEGMENTS}
						value={value.percent}
					/>
				</SettingsRow>
			</SettingsGroup>
		</>
	);
}
