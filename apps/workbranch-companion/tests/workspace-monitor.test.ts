import { describe, expect, it } from "vitest";
import type { GlobalState } from "../src/domain/model";
import { startWorkspaceMonitor } from "../src/infrastructure/workspaceMonitor";

const FIRST_STATE: GlobalState = {
	projects: [{ name: "workbranch", root: "/tmp/workbranch", tasks: [] }],
	errors: [],
};

const SECOND_STATE: GlobalState = {
	projects: [
		{
			name: "workbranch",
			root: "/tmp/workbranch",
			tasks: [
				{
					name: "feat-login",
					path: "/tmp/workbranch/feat-login",
					memoTitle: "",
					notiCount: 0,
					updatedAt: 20,
					repos: [],
					plans: [],
				},
			],
		},
	],
	errors: [],
};

type Deferred<T> = {
	readonly promise: Promise<T>;
	readonly resolve: (value: T) => void;
};

function deferred<T>(): Deferred<T> {
	let resolveValue: ((value: T) => void) | undefined;
	const promise = new Promise<T>((resolve) => {
		resolveValue = resolve;
	});
	if (resolveValue === undefined) {
		throw new Error("deferred resolver was not initialized");
	}
	return { promise, resolve: resolveValue };
}

function nextMicrotask(): Promise<void> {
	return Promise.resolve();
}

describe("startWorkspaceMonitor", () => {
	it("refreshes again when a watched root changes", async () => {
		const rendered: GlobalState[] = [];
		const watchedRoots: string[][] = [];
		let rootChanged: (() => void) | undefined;
		const states = [FIRST_STATE, SECOND_STATE];

		const monitor = await startWorkspaceMonitor({
			refresh: () => {
				const state = states.shift();
				if (state === undefined) {
					throw new Error("unexpected refresh");
				}
				return Promise.resolve(state);
			},
			onState: (state) => {
				rendered.push(state);
			},
			onError: (error) => {
				throw error;
			},
			watchRoots: (roots) => {
				watchedRoots.push([...roots]);
				return Promise.resolve();
			},
			onRootChanged: (callback) => {
				rootChanged = callback;
				return Promise.resolve(() => {
					rootChanged = undefined;
				});
			},
		});

		rootChanged?.();
		await monitor.settle();
		monitor.stop();

		expect(watchedRoots).toEqual([["/tmp/workbranch"]]);
		expect(rendered).toEqual([FIRST_STATE, SECOND_STATE]);
	});

	it("coalesces root changes while refresh is in flight", async () => {
		let rootChanged: (() => void) | undefined;
		let refreshCalls = 0;
		const inFlight = deferred<GlobalState>();

		const monitor = await startWorkspaceMonitor({
			refresh: () => {
				refreshCalls += 1;
				return refreshCalls === 1
					? Promise.resolve(FIRST_STATE)
					: inFlight.promise;
			},
			onState: () => {},
			onError: (error) => {
				throw error;
			},
			watchRoots: () => Promise.resolve(),
			onRootChanged: (callback) => {
				rootChanged = callback;
				return Promise.resolve(() => {
					rootChanged = undefined;
				});
			},
		});

		rootChanged?.();
		rootChanged?.();
		rootChanged?.();
		await nextMicrotask();

		expect(refreshCalls).toBe(2);
		inFlight.resolve(SECOND_STATE);
		await monitor.settle();
		monitor.stop();
	});

	it("runs another trailing refresh when a root changes during the queued refresh", async () => {
		let rootChanged: (() => void) | undefined;
		let refreshCalls = 0;
		const firstManualRefresh = deferred<GlobalState>();
		const queuedRefresh = deferred<GlobalState>();

		const monitor = await startWorkspaceMonitor({
			refresh: () => {
				refreshCalls += 1;
				if (refreshCalls === 1) {
					return Promise.resolve(FIRST_STATE);
				}
				if (refreshCalls === 2) {
					return firstManualRefresh.promise;
				}
				if (refreshCalls === 3) {
					return queuedRefresh.promise;
				}
				return Promise.resolve(SECOND_STATE);
			},
			onState: () => {},
			onError: (error) => {
				throw error;
			},
			watchRoots: () => Promise.resolve(),
			onRootChanged: (callback) => {
				rootChanged = callback;
				return Promise.resolve(() => {
					rootChanged = undefined;
				});
			},
		});

		rootChanged?.();
		rootChanged?.();
		await nextMicrotask();
		expect(refreshCalls).toBe(2);

		firstManualRefresh.resolve(SECOND_STATE);
		await nextMicrotask();
		await nextMicrotask();
		expect(refreshCalls).toBe(3);

		rootChanged?.();
		await nextMicrotask();
		await nextMicrotask();
		expect(refreshCalls).toBe(3);

		queuedRefresh.resolve(SECOND_STATE);
		await monitor.settle();
		expect(refreshCalls).toBe(4);
		monitor.stop();
	});

	it("ignores late root change callbacks after stop", async () => {
		let rootChanged: (() => void) | undefined;
		let refreshCalls = 0;

		const monitor = await startWorkspaceMonitor({
			refresh: () => {
				refreshCalls += 1;
				return Promise.resolve(FIRST_STATE);
			},
			onState: () => {},
			onError: (error) => {
				throw error;
			},
			watchRoots: () => Promise.resolve(),
			onRootChanged: (callback) => {
				rootChanged = callback;
				return Promise.resolve(() => {});
			},
		});

		expect(refreshCalls).toBe(1);
		monitor.stop();
		rootChanged?.();
		await monitor.settle();

		expect(refreshCalls).toBe(1);
	});

	it("starts heartbeat refreshes and clears the heartbeat on stop", async () => {
		let heartbeatCallback: (() => void) | undefined;
		let clearedHandle = 0;
		let refreshCalls = 0;
		const monitor = await startWorkspaceMonitor({
			refresh: () => {
				refreshCalls += 1;
				return Promise.resolve(FIRST_STATE);
			},
			onState: () => {},
			onError: (error) => {
				throw error;
			},
			watchRoots: () => Promise.resolve(),
			onRootChanged: () => Promise.resolve(() => {}),
			heartbeatMs: 300_000,
			setTimer: (callback, milliseconds) => {
				expect(milliseconds).toBe(300_000);
				heartbeatCallback = callback;
				return 7;
			},
			clearTimer: (handle) => {
				clearedHandle = handle;
			},
		});

		expect(refreshCalls).toBe(1);
		heartbeatCallback?.();
		await monitor.settle();
		expect(refreshCalls).toBe(2);

		monitor.stop();
		expect(clearedHandle).toBe(7);
	});
});
