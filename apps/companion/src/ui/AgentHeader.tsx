import type { CompanionTheme } from "../application/preferences";
import type { MenuSummary } from "../application/state";

export type AgentHeaderProps = {
	readonly theme: CompanionTheme;
	readonly summary: MenuSummary;
	readonly status: string;
	readonly onCheckUpdates: () => void;
	readonly updateAvailable: boolean;
	readonly onQuit: () => void;
};

function AgentInventory({ summary }: { readonly summary: MenuSummary }) {
	return (
		<span className="agent-inventory">
			{summary.projectCount}{" "}
			{summary.projectCount === 1 ? "project" : "projects"} ·{" "}
			{summary.taskCount} {summary.taskCount === 1 ? "task" : "tasks"}
		</span>
	);
}

function AgentControls({
	status,
	onCheckUpdates,
	updateAvailable,
	onQuit,
}: Omit<AgentHeaderProps, "theme" | "summary">) {
	return (
		<div
			className="agent-controls"
			aria-label="Companion controls"
			role="toolbar"
		>
			<span className="toolbar-status-sr" aria-live="polite" role="status">
				{status}
			</span>
			<button
				aria-label={updateAvailable ? "Updates available" : "Check for updates"}
				className="agent-control agent-control-update"
				data-update-available={updateAvailable ? "true" : undefined}
				onClick={onCheckUpdates}
				type="button"
			>
				<span aria-hidden="true" className="agent-update-glyph">
					↓
				</span>
			</button>
			<button
				aria-label="Quit Companion"
				className="agent-control agent-control-quit"
				onClick={onQuit}
				type="button"
			>
				<span aria-hidden="true">⏻</span>
			</button>
		</div>
	);
}

export function AgentHeader({
	theme,
	summary,
	status,
	onCheckUpdates,
	updateAvailable,
	onQuit,
}: AgentHeaderProps) {
	const controls = {
		status,
		onCheckUpdates,
		updateAvailable,
		onQuit,
	};

	return (
		<section className="agent-header" data-agent-header={theme}>
			<div className="agent-header-row">
				<div className="agent-header-copy">
					<h1>Workbranch Companion</h1>
					<AgentInventory summary={summary} />
				</div>
				<AgentControls {...controls} />
			</div>
		</section>
	);
}
