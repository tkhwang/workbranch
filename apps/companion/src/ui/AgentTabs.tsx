export type CompanionView = "main" | "activity" | "settings";

export type AgentTabsProps = {
	readonly currentView: CompanionView;
	readonly onViewChange: (view: CompanionView) => void;
};

type AgentTab = {
	readonly view: CompanionView;
	readonly label: string;
};

const AGENT_TABS: readonly AgentTab[] = [
	{ view: "main", label: "Main" },
	{ view: "activity", label: "Activity" },
	{ view: "settings", label: "Settings" },
];

export function AgentTabs({ currentView, onViewChange }: AgentTabsProps) {
	return (
		<nav className="agent-tabs" aria-label="Companion views">
			{AGENT_TABS.map(({ view, label }) => (
				<button
					aria-current={view === currentView ? "page" : undefined}
					className="agent-tab"
					data-active={view === currentView ? "true" : "false"}
					key={view}
					onClick={() => onViewChange(view)}
					type="button"
				>
					{label}
				</button>
			))}
		</nav>
	);
}
