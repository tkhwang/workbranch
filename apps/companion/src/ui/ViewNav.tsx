export type CompanionView = "main" | "activity" | "settings";

type ViewNavItem = {
	readonly view: CompanionView;
	readonly label: string;
	readonly ariaLabel: string;
};

type ViewNavProps = {
	readonly currentView: CompanionView;
	readonly onViewChange: (view: CompanionView) => void;
};

const VIEW_NAV_ITEMS: readonly ViewNavItem[] = [
	{ view: "main", label: "Main", ariaLabel: "Open Main View" },
	{
		view: "activity",
		label: "Activity",
		ariaLabel: "Open Activity report",
	},
	{ view: "settings", label: "Settings", ariaLabel: "Open Settings" },
] as const;

function ViewIcon({ view }: { readonly view: CompanionView }) {
	switch (view) {
		case "main":
			return (
				<svg aria-hidden="true" className="view-nav-icon" viewBox="0 0 24 24">
					<path d="M4 6.5h16" />
					<path d="M4 12h16" />
					<path d="M4 17.5h10" />
				</svg>
			);
		case "activity":
			return (
				<svg aria-hidden="true" className="view-nav-icon" viewBox="0 0 24 24">
					<path d="M5 18V9" />
					<path d="M12 18V5" />
					<path d="M19 18v-6" />
					<path d="M3.5 18.5h17" />
				</svg>
			);
		case "settings":
			return (
				<svg aria-hidden="true" className="view-nav-icon" viewBox="0 0 24 24">
					<path d="M12 8.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7Z" />
					<path d="M12 3.5v3" />
					<path d="M12 17.5v3" />
					<path d="m5.99 5.99 2.12 2.12" />
					<path d="m15.89 15.89 2.12 2.12" />
					<path d="M3.5 12h3" />
					<path d="M17.5 12h3" />
					<path d="m5.99 18.01 2.12-2.12" />
					<path d="m15.89 8.11 2.12-2.12" />
				</svg>
			);
	}
}

export function ViewNav({ currentView, onViewChange }: ViewNavProps) {
	return (
		<nav className="view-nav" aria-label="Companion views">
			{VIEW_NAV_ITEMS.map((item) => {
				const selected = item.view === currentView;
				return (
					<button
						aria-current={selected ? "page" : undefined}
						aria-label={item.ariaLabel}
						className="view-nav-button"
						data-active={selected ? "true" : "false"}
						key={item.view}
						onClick={() => onViewChange(item.view)}
						type="button"
					>
						<ViewIcon view={item.view} />
						<span>{item.label}</span>
					</button>
				);
			})}
		</nav>
	);
}
