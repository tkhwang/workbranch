import type { CompanionTheme } from "../application/preferences";
import type { MenuSummary } from "../application/state";

export type AgentHeaderProps = {
	readonly theme: CompanionTheme;
	readonly summary: MenuSummary;
	readonly status: string;
	readonly onRefresh: () => void;
	readonly onQuit: () => void;
};

function AgentInventory({ summary }: { readonly summary: MenuSummary }) {
	return (
		<span className="agent-inventory">
			{summary.projectCount} projects · {summary.taskCount} tasks
		</span>
	);
}

function AgentControls({
	status,
	onRefresh,
	onQuit,
}: Pick<AgentHeaderProps, "status" | "onRefresh" | "onQuit">) {
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
				aria-label="Refresh tasks"
				className="agent-control"
				onClick={onRefresh}
				type="button"
			>
				<span aria-hidden="true">↻</span>
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
	onRefresh,
	onQuit,
}: AgentHeaderProps) {
	const controls = { status, onRefresh, onQuit };

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
