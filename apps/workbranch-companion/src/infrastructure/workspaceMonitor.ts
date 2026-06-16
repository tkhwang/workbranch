import type { GlobalState } from "../domain/model";

export type WorkspaceMonitor = {
	readonly stop: () => void;
	readonly settle: () => Promise<void>;
};

export type WorkspaceMonitorDeps = {
	readonly refresh: () => Promise<GlobalState>;
	readonly onState: (state: GlobalState) => void;
	readonly onError: (error: unknown) => void;
	readonly watchRoots: (roots: readonly string[]) => Promise<void>;
	readonly onRootChanged: (callback: () => void) => Promise<() => void>;
};

export async function startWorkspaceMonitor(
	deps: WorkspaceMonitorDeps,
): Promise<WorkspaceMonitor> {
	let stopped = false;
	let watchedRoots: readonly string[] = [];
	let pending = Promise.resolve();
	const refreshAndWatch = async (): Promise<void> => {
		try {
			const state = await deps.refresh();
			if (stopped) {
				return;
			}
			deps.onState(state);
			const roots = state.projects.map((project) => project.root);
			if (!sameRoots(watchedRoots, roots)) {
				await deps.watchRoots(roots);
				watchedRoots = roots;
			}
		} catch (error) {
			deps.onError(error);
		}
	};
	const scheduleRefresh = (): void => {
		pending = refreshAndWatch();
	};

	scheduleRefresh();
	await pending;
	const unlisten = await deps.onRootChanged(scheduleRefresh);

	return {
		stop: () => {
			stopped = true;
			unlisten();
		},
		settle: () => pending,
	};
}

function sameRoots(left: readonly string[], right: readonly string[]): boolean {
	return (
		left.length === right.length &&
		left.every((root, index) => root === right[index])
	);
}
