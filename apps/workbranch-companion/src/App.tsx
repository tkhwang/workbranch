import { useCallback, useEffect, useMemo, useState } from "react";
import { createActivityRefresh } from "./application/activity";
import {
	buildMenuModel,
	type MenuModel,
	type MenuSummary,
} from "./application/state";
import type { GlobalState, Task } from "./domain/model";
import {
	appendActivityEvents,
	type CompanionCommand,
	onRootChanged,
	refreshStatus,
	runAction,
	watchRoots,
} from "./infrastructure/tauriClient";
import { startWorkspaceMonitor } from "./infrastructure/workspaceMonitor";
import { ProjectGroup } from "./ui/ProjectGroup";
import type { TaskActionKind } from "./ui/TaskRow";

const EMPTY_STATE: GlobalState = { projects: [], errors: [] };

function currentEpochSeconds(): number {
	return Math.floor(Date.now() / 1000);
}

function commandForTaskAction(
	task: Task,
	kind: TaskActionKind,
): CompanionCommand {
	switch (kind) {
		case "ide":
			return { kind: "ide", task: task.name };
		case "terminal":
			return { kind: "terminal", task: task.name };
		case "finder":
			return { kind: "finder", task: task.name };
	}
}

function plural(count: number, word: string): string {
	return count === 1 ? word : `${word}s`;
}

function AppSummary({ summary }: { readonly summary: MenuSummary }) {
	const { projectCount, taskCount, active, blocked, notifications } = summary;
	return (
		<div className="app-summary">
			<span className="app-inventory">
				{taskCount === 0
					? "No tasks"
					: `${projectCount} ${plural(projectCount, "project")} · ${taskCount} ${plural(taskCount, "task")}`}
			</span>
			<span className="app-badges">
				{active > 0 ? (
					<span
						className="badge badge-active"
						title={`${active} in progress`}
						aria-label={`${active} in progress`}
						role="img"
					>
						▶ {active}
					</span>
				) : null}
				{blocked > 0 ? (
					<span
						className="badge badge-blocked"
						title={`${blocked} blocked`}
						aria-label={`${blocked} blocked`}
						role="img"
					>
						⚠ {blocked}
					</span>
				) : null}
				{notifications > 0 ? (
					<span
						className="badge badge-noti"
						title={`${notifications} notifications`}
						aria-label={`${notifications} notifications`}
						role="img"
					>
						🔔 {notifications}
					</span>
				) : null}
			</span>
		</div>
	);
}

export function App() {
	const [state, setState] = useState<GlobalState>(EMPTY_STATE);
	const [status, setStatus] = useState("Ready");
	const model: MenuModel = buildMenuModel(state);
	const refreshWithActivity = useMemo(
		() =>
			createActivityRefresh({
				refresh: refreshStatus,
				append: appendActivityEvents,
				now: currentEpochSeconds,
			}),
		[],
	);

	const showError = useCallback((error: unknown) => {
		if (error instanceof Error) {
			setStatus(error.message);
		} else {
			setStatus(String(error));
		}
	}, []);

	const applyState = useCallback((next: GlobalState) => {
		setState(next);
		setStatus("Updated");
	}, []);

	const refresh = useCallback(async () => {
		try {
			applyState(await refreshWithActivity());
		} catch (error) {
			showError(error);
		}
	}, [applyState, refreshWithActivity, showError]);

	const handleTaskAction = useCallback(
		async (root: string, task: Task, kind: TaskActionKind) => {
			const command = commandForTaskAction(task, kind);
			try {
				await runAction(command, root);
				applyState(await refreshWithActivity());
				setStatus("Action complete");
			} catch (error) {
				showError(error);
			}
		},
		[applyState, refreshWithActivity, showError],
	);

	useEffect(() => {
		let stop: (() => void) | undefined;
		let cancelled = false;
		void startWorkspaceMonitor({
			refresh: refreshWithActivity,
			onState: applyState,
			onError: showError,
			watchRoots,
			onRootChanged,
			heartbeatMs: 5 * 60 * 1000,
			setTimer: (callback, milliseconds) =>
				window.setInterval(callback, milliseconds),
			clearTimer: (handle) => {
				window.clearInterval(handle);
			},
		})
			.then((monitor) => {
				if (cancelled) {
					monitor.stop();
				} else {
					stop = monitor.stop;
				}
			})
			.catch(showError);
		return () => {
			cancelled = true;
			stop?.();
		};
	}, [applyState, refreshWithActivity, showError]);

	return (
		<main>
			<header>
				<AppSummary summary={model.summary} />
				<button
					type="button"
					onClick={() => void refresh()}
					aria-label="refresh"
				>
					↻
				</button>
			</header>
			<section>
				{model.groups.length === 0 ? (
					<p className="empty">No workbranch tasks registered.</p>
				) : null}
				{model.groups.map((group) => (
					<ProjectGroup
						key={group.root}
						group={group}
						onAction={(root, task, kind) =>
							void handleTaskAction(root, task, kind)
						}
					/>
				))}
			</section>
			{model.errors.map((error) => (
				<p className="error" key={error.root}>
					{error.root}: {error.message}
				</p>
			))}
			<footer>{status}</footer>
		</main>
	);
}
