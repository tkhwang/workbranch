import type { GlobalState } from "../domain/model";

type TimerHandle = number;

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
	readonly heartbeatMs?: number;
	readonly setTimer?: (
		callback: () => void,
		milliseconds: number,
	) => TimerHandle;
	readonly clearTimer?: (handle: TimerHandle) => void;
};

export async function startWorkspaceMonitor(
	deps: WorkspaceMonitorDeps,
): Promise<WorkspaceMonitor> {
	let stopped = false;
	let running = false;
	let queued = false;
	let watchedRoots: readonly string[] = [];
	let pending = Promise.resolve();
	let heartbeat: TimerHandle | undefined;

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

	const drainRefreshQueue = async (): Promise<void> => {
		running = true;
		try {
			do {
				queued = false;
				await refreshAndWatch();
			} while (queued && !stopped);
		} finally {
			running = false;
		}
	};

	const scheduleRefresh = (): void => {
		if (running) {
			queued = true;
			return;
		}
		pending = drainRefreshQueue();
	};

	scheduleRefresh();
	await pending;
	const unlisten = await deps.onRootChanged(scheduleRefresh);
	if (deps.heartbeatMs !== undefined) {
		const setTimer = deps.setTimer ?? window.setInterval;
		heartbeat = setTimer(scheduleRefresh, deps.heartbeatMs);
	}

	return {
		stop: () => {
			stopped = true;
			if (heartbeat !== undefined) {
				const clearTimer = deps.clearTimer ?? window.clearInterval;
				clearTimer(heartbeat);
			}
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
