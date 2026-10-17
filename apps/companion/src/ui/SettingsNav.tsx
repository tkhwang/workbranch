import { SettingsIcon } from "./SettingsIcon";

export type SettingsCategory =
	| "general"
	| "connections"
	| "menu-bar"
	| "screen-saver"
	| "appearance";

export type SettingsAttention = Partial<Record<SettingsCategory, boolean>>;

export const SETTINGS_CATEGORIES: readonly {
	readonly category: SettingsCategory;
	readonly label: string;
}[] = [
	{ category: "general", label: "General" },
	{ category: "connections", label: "Connections" },
	{ category: "menu-bar", label: "Menu Bar" },
	{ category: "screen-saver", label: "Screen Saver" },
	{ category: "appearance", label: "Appearance" },
];

/** "01 · General": the page's place in the tab row, then its name. */
export function settingsEyebrow(category: SettingsCategory): string {
	const index = SETTINGS_CATEGORIES.findIndex(
		(entry) => entry.category === category,
	);
	const label = SETTINGS_CATEGORIES[index]?.label ?? category;
	return `${String(index + 1).padStart(2, "0")} · ${label}`;
}

type SettingsNavProps = {
	readonly current: SettingsCategory;
	readonly attention: SettingsAttention;
	readonly onChange: (category: SettingsCategory) => void;
};

export function SettingsNav({
	current,
	attention,
	onChange,
}: SettingsNavProps) {
	return (
		<nav aria-label="Settings categories" className="settings-nav">
			{SETTINGS_CATEGORIES.map(({ category, label }) => {
				const active = category === current;
				const flagged = attention[category] === true;
				return (
					<button
						aria-current={active ? "page" : undefined}
						aria-label={flagged ? `${label}, needs attention` : undefined}
						className="settings-nav-tab"
						data-active={active ? "true" : "false"}
						key={category}
						onClick={() => onChange(category)}
						type="button"
					>
						<SettingsIcon name={category} />
						<span>{label}</span>
						{flagged ? (
							<span aria-hidden="true" className="settings-nav-dot" />
						) : null}
					</button>
				);
			})}
		</nav>
	);
}
