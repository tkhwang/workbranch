import { useCallback, useEffect, useMemo, useState } from "react";
import { createActivityRefresh } from "./application/activity";
import { buildMenuModel, type MenuModel } from "./application/state";
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
import { type TaskActionKind, TaskRow } from "./ui/TaskRow";

const EMPTY_STATE: GlobalState = { projects: [], errors: [] };

function currentEpochSeconds(): number {
	return Math.floor(Date.now() / 1000);
}

function commandForTaskAction(
	task: Task,
	kind: TaskActionKind,
): CompanionCommand | undefined {
	switch (kind) {
		case "memoEdit": {
			const text = window.prompt(`Memo for ${task.name}`, task.memoTitle);
			return text === null
				? undefined
				: { kind: "memo", task: task.name, text };
		}
		case "memoClear":
			return { kind: "memoClear", task: task.name };
		case "notiClear":
			return { kind: "notiClear", task: task.name };
		case "finder":
			return { kind: "finder", task: task.name };
		case "ide":
			return { kind: "ide", task: task.name };
		case "terminal":
			return { kind: "terminal", task: task.name };
		case "copyPath":
			return { kind: "copyPath", path: task.path };
	}
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
			if (command === undefined) {
				return;
			}
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
				<h1>{model.title}</h1>
				<button
					type="button"
					onClick={() => void refresh()}
					aria-label="refresh"
				>
					↻
				</button>
			</header>
			<section>
				{model.rows.length === 0 ? (
					<p className="empty">No workbranch tasks configured.</p>
				) : null}
				{model.rows.map((row) => (
					<TaskRow
						key={`${row.root}-${row.task.name}`}
						project={row.project}
						root={row.root}
						task={row.task}
						expanded={row.expanded}
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
