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
});
