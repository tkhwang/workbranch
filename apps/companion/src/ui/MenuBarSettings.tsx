import {
	isIconOnly,
	MENU_BAR_ITEM_OPTIONS,
	MENU_BAR_PERCENT_OPTIONS,
	type MenuBarConfig,
	menuBarSampleTitle,
} from "../application/menuBar";

type MenuBarSettingsProps = {
	readonly value: MenuBarConfig;
	readonly onChange: (config: MenuBarConfig) => void;
};

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
 * produce with sample numbers, so each toggle's effect is visible at once.
 */
export function MenuBarSettings({ value, onChange }: MenuBarSettingsProps) {
	const title = menuBarSampleTitle(value);
	const percentDisabled =
		!value.claude5h && !value.claudeWeekly && !value.codexWeekly;
	return (
		<div className="menu-bar-settings">
			<div className="menu-bar-preview">
				<span className="menu-bar-preview-label">Preview</span>
				<span className="menu-bar-sample" data-testid="menu-bar-preview">
					<TrayGhost />
					{title === "" ? null : (
						<span className="menu-bar-sample-text">{title}</span>
					)}
				</span>
			</div>
			<fieldset className="menu-bar-items" aria-label="Menu bar items">
				{MENU_BAR_ITEM_OPTIONS.map((option) => {
					const selected = value[option.item];
					return (
						<button
							aria-label={`Show ${option.label} in the menu bar`}
							aria-pressed={selected}
							className="menu-bar-item"
							data-active={selected ? "true" : "false"}
							key={option.item}
							onClick={() => onChange({ ...value, [option.item]: !selected })}
							type="button"
						>
							<span className="menu-bar-item-check" aria-hidden="true">
								{selected ? "✓" : ""}
							</span>
							<span className="menu-bar-item-text">
								<span className="menu-bar-item-label">{option.label}</span>
								<span className="menu-bar-item-detail">{option.detail}</span>
							</span>
						</button>
					);
				})}
			</fieldset>
			<fieldset
				className="agent-theme-picker menu-bar-percent"
				aria-label="Limit percent"
				disabled={percentDisabled}
			>
				{MENU_BAR_PERCENT_OPTIONS.map((option) => {
					const selected = option.value === value.percent;
					return (
						<button
							aria-label={`Show limits as ${option.label}`}
							aria-pressed={selected}
							className="agent-theme-button"
							data-active={selected ? "true" : "false"}
							key={option.value}
							onClick={() => onChange({ ...value, percent: option.value })}
							type="button"
						>
							{option.label}
						</button>
					);
				})}
			</fieldset>
			<p className="settings-hint">
				{isIconOnly(value)
					? "Nothing picked: the menu bar shows the icon alone."
					: "Sample numbers. The menu bar updates every minute; a limit reading too old to trust shows as –."}
			</p>
		</div>
	);
}
