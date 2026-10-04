import { expect, it, vi } from "vitest";
import { createActivityRefresh } from "../src/application/activity";

it("refreshes projects without producing legacy brief activity", async () => {
	const project = { name: "p", root: "/p", tasks: [], baseRepos: [] };
	const state = { projects: [project], errors: [] };
	const append = vi.fn();
	const refresh = createActivityRefresh({
		refresh: async () => state,
		refreshRoot: async () => project,
		append,
		now: () => 100,
	});
	expect(await refresh.all()).toEqual(state);
	expect(await refresh.root("/p")).toEqual(project);
	expect(append).not.toHaveBeenCalled();
});
