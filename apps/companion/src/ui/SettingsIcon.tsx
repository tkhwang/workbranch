export type SettingsIconName =
	| "general"
	| "menu-bar"
	| "screen-saver"
	| "appearance"
	| "connections"
	| "download"
	| "info"
	| "check"
	| "alert";

/** One stroke path per icon, drawn on a 24px grid. */
const PATHS: Record<SettingsIconName, string> = {
	general:
		"M3 5h10M17 5h4M3 12h4M11 12h10M3 19h12M19 19h2M13 5a2 2 0 1 0 4 0a2 2 0 1 0-4 0M7 12a2 2 0 1 0 4 0a2 2 0 1 0-4 0M15 19a2 2 0 1 0 4 0a2 2 0 1 0-4 0",
	"menu-bar":
		"M5 4h14a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zM3 9h18M15 6.5h3",
	"screen-saver":
		"M5 4h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zM8 20h8M12 16v4",
	appearance: "M4 7V5h16v2M9 19h6M12 5v14",
	connections: "M9 2v5M15 2v5M7 7h10v4a5 5 0 0 1-10 0V7zM12 16v6",
	download: "M12 4v11M7 10l5 5 5-5M5 20h14",
	info: "M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M12 11v6M12 7.5v.5",
	check: "M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M8 12.5l2.5 2.5L16 9.5",
	alert: "M12 3l9.5 17h-19L12 3zM12 10v4.5M12 17.5v.5",
};

export function SettingsIcon({ name }: { readonly name: SettingsIconName }) {
	return (
		<svg
			aria-hidden="true"
			className="settings-icon"
			fill="none"
			stroke="currentColor"
			strokeLinecap="round"
			strokeLinejoin="round"
			strokeWidth="1.7"
			viewBox="0 0 24 24"
		>
			<path d={PATHS[name]} />
		</svg>
	);
}
