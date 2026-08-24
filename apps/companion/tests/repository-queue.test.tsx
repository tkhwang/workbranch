import type { EffectCallback } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { afterEach, describe, expect, it, vi } from "vitest";
import { buildMainViewModel } from "../src/application/state";
import type { GlobalState, PlanStatus, Task } from "../src/domain/model";
import { RepositoryQueue } from "../src/ui/RepositoryQueue";

const effectCleanups = vi.hoisted((): Array<() => void> => []);

vi.mock("react", async (importOriginal) => {
	const react = await importOriginal<typeof import("react")>();
	return {
		...react,
		useEffect: (effect: EffectCallback) => {
			const cleanup = effect();
			if (cleanup !== undefined) effectCleanups.push(cleanup);
		},
	};
});

function task(
	name: string,
	status: PlanStatus,
	updatedAt: number,
	repos: Task["repos"],
): Task {
	return {
		name,
		path: `/tmp/acme/${name}`,
		notiCount: 0,
		updatedAt,
		repos,
		plans: [
			{
				title: `${name} plan`,
				index: 0,
				status,
				progressDone: status === "review" ? 3 : 1,
				progressTotal: 4,
				currentItem: `${name} current work`,
				steps: [],
			},
		],
	};
}

const dirtyRepo: Task["repos"][number] = {
	name: "frontend",
	branch: "feature/cpq-task-a",
	dirty: true,
	activityAvailable: true,
	ahead: 2,
	behind: 0,
	changedFiles: 7,
	lastCommitSubject: "implement companion activity feed",
	lastCommitAt: 3_500,
};

const cleanRepo: Task["repos"][number] = {
	name: "backend",
	branch: "feature/cpq-task-a",
	dirty: false,
	activityAvailable: true,
	ahead: 0,
	behind: 1,
	changedFiles: 0,
	lastCommitSubject: "document stage board",
	lastCommitAt: 400,
};

const state: GlobalState = {
	projects: [
		{
			name: "monask-fullstack",
			root: "/tmp/monask-fullstack",
			tasks: [
				task("review-task", "review", 30, [dirtyRepo, cleanRepo]),
				task("execution-task", "in-progress", 20, [
					{ ...dirtyRepo, name: "workbranch", ahead: 0 },
				]),
				task("planning-task", "planning", 10, [{ ...cleanRepo, name: "docs" }]),
				task("clean-todo", "todo", 50, [{ ...cleanRepo, name: "inactive" }]),
			],
		},
	],
	errors: [],
};
const main = buildMainViewModel(state);

afterEach(() => {
	for (const cleanup of effectCleanups.splice(0)) cleanup();
	vi.useRealTimers();
	vi.unstubAllGlobals();
});

describe("RepositoryQueue", () => {
	it("renders every repository from the active matrix without inactive tasks", () => {
		const html = renderToStaticMarkup(
			<RepositoryQueue
				nowSeconds={3_600}
				onAction={() => undefined}
				rows={main.repositoryRows}
				selectedKey={undefined}
				theme="claude"
			/>,
		);

		expect(html).toContain('aria-label="All repositories"');
		expect(html).toContain("ALL REPOSITORIES 4");
		expect(html.match(/data-repository-task=/g)).toHaveLength(3);
		expect(html).not.toContain('data-highlighted="true"');
		expect(html).toContain("frontend");
		expect(html).toContain("backend");
		expect(html).toContain("workbranch");
		expect(html).toContain("docs");
		expect(html).not.toContain("inactive");
	});

	it("renders repo facts, current work, relative commit time, and task actions", () => {
		const html = renderToStaticMarkup(
			<RepositoryQueue
				nowSeconds={3_600}
				onAction={() => undefined}
				rows={main.repositoryRows}
				selectedKey={undefined}
				theme="codex"
			/>,
		);

		expect(html).toContain("DIRTY 7 FILES · AHEAD 2");
		expect(html).toContain('class="repo-name repo-dirty" title="frontend"');
		expect(html).toContain("CLEAN · BEHIND 1");
		expect(html).toContain(
			"last commit: implement companion activity feed · 1m",
		);
		expect(html).toContain("review-task current work");
		expect(html).toContain('aria-label="open review-task in IDE"');
		expect(html).toContain('aria-label="open review-task in terminal"');
		expect(html).toContain('aria-label="open review-task in Finder"');
	});

	it("scrolls only the selected task into the nearest visible position", () => {
		const scrollIntoView = vi.fn();
		vi.stubGlobal("document", {
			getElementById: () => ({ scrollIntoView }),
		});
		const selectedKey = main.repositoryRows[1]?.key;

		const html = renderToStaticMarkup(
			<RepositoryQueue
				nowSeconds={3_600}
				onAction={() => undefined}
				rows={main.repositoryRows}
				selectedKey={selectedKey}
				theme="claude"
			/>,
		);

		expect(html.match(/data-highlighted="true"/g)).toHaveLength(1);
		expect(html.match(/aria-current="true"/g)).toHaveLength(1);
		expect(scrollIntoView).toHaveBeenCalledWith({ block: "nearest" });
	});

	it("schedules minute refreshes when no fixed time is provided", () => {
		vi.useFakeTimers();
		vi.stubGlobal("window", {
			setInterval: globalThis.setInterval,
			clearInterval: globalThis.clearInterval,
		});

		renderToStaticMarkup(
			<RepositoryQueue
				onAction={() => undefined}
				rows={main.repositoryRows}
				selectedKey={undefined}
				theme="claude"
			/>,
		);

		expect(vi.getTimerCount()).toBe(1);
	});
});
