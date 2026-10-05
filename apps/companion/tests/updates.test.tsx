import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import {
	companionRestartPending,
	createUpdateController,
	EMPTY_UPDATE_STATE,
	type UpdateRunResult,
	type UpdateState,
	type UpdateStatus,
	updateActionLabel,
	updateTargets,
} from "../src/application/updates";
import { UpdatePanel } from "../src/ui/UpdatePanel";

const current: UpdateStatus = {
	brewPath: "/opt/homebrew/bin/brew",
	fetchError: null,
	runningVersion: "2.23.0",
	selfUpdateSupported: true,
	cli: { installed: "2.26.0", latest: "2.26.0", outdated: false },
	companion: { installed: "2.23.0", latest: "2.23.0", outdated: false },
};
const outdated: UpdateStatus = {
	...current,
	cli: { installed: "2.25.1", latest: "2.26.0", outdated: true },
	companion: { installed: "2.23.0", latest: "2.24.0", outdated: true },
};
const ok: UpdateRunResult = { exitCode: 0, output: "", restartRequired: false };

function services(overrides: {
	inspect?: (fetch: boolean) => Promise<UpdateStatus>;
	apply?: () => Promise<UpdateRunResult>;
	relaunch?: () => Promise<void>;
	onUpdated?: () => void;
}) {
	return {
		inspect: vi.fn(overrides.inspect ?? (async () => outdated)),
		apply: vi.fn(overrides.apply ?? (async () => ok)),
		subscribe: vi.fn(async () => () => {}),
		relaunch: vi.fn(overrides.relaunch ?? (async () => {})),
		id: () => "op",
		onUpdated: overrides.onUpdated,
	};
}

function render(state: Partial<UpdateState>) {
	return renderToStaticMarkup(
		<UpdatePanel
			theme="claude"
			state={{ ...EMPTY_UPDATE_STATE, ...state }}
			onCheck={() => {}}
			onApply={() => {}}
			onClose={() => {}}
		/>,
	);
}

describe("update targets", () => {
	it("updates only installed, outdated packages and skips self-update in dev builds", () => {
		expect(updateTargets(null)).toEqual([]);
		expect(updateTargets(current)).toEqual([]);
		expect(updateTargets(outdated)).toEqual(["cli", "companion"]);
		expect(updateTargets({ ...outdated, selfUpdateSupported: false })).toEqual([
			"cli",
		]);
	});

	it("labels the restart that a Companion update causes", () => {
		expect(updateActionLabel(["cli"])).toBe("CLI 업데이트");
		expect(updateActionLabel(["companion"])).toBe(
			"Companion 업데이트 후 재시작",
		);
		expect(updateActionLabel(["cli", "companion"])).toBe(
			"모두 업데이트 후 재시작",
		);
	});

	it("detects a newer cask install that the running app has not loaded", () => {
		expect(companionRestartPending(current)).toBe(false);
		expect(
			companionRestartPending({
				...current,
				companion: { installed: "2.24.0", latest: "2.24.0", outdated: false },
			}),
		).toBe(true);
	});
});

describe("update controller", () => {
	it("fetches the latest Homebrew metadata when checking", async () => {
		const deps = services({});
		const states: UpdateState[] = [];
		const controller = createUpdateController(deps, (s) => states.push(s));
		await controller.check();
		expect(deps.inspect).toHaveBeenCalledWith(true);
		expect(deps.apply).not.toHaveBeenCalled();
		expect(states[states.length - 1]).toMatchObject({
			status: outdated,
			checking: false,
		});
		controller.dispose();
	});

	it("updates the CLI, rereads versions without fetching and notifies", async () => {
		const onUpdated = vi.fn();
		const deps = services({
			inspect: async () => ({ ...outdated, companion: current.companion }),
			onUpdated,
		});
		let state = EMPTY_UPDATE_STATE;
		const controller = createUpdateController(deps, (s) => {
			state = s;
		});
		await controller.check();
		deps.inspect.mockResolvedValue(current);
		await expect(controller.apply()).resolves.toBe(true);
		expect(deps.apply).toHaveBeenCalledWith(["cli"], "op");
		expect(deps.inspect).toHaveBeenLastCalledWith(false);
		expect(deps.relaunch).not.toHaveBeenCalled();
		expect(onUpdated).toHaveBeenCalledOnce();
		expect(state).toMatchObject({
			status: current,
			updating: false,
			notice: "CLI 업데이트를 완료했습니다.",
		});
		controller.dispose();
	});

	it("restarts after a Companion update instead of rereading versions", async () => {
		const deps = services({
			apply: async () => ({ ...ok, restartRequired: true }),
		});
		let state = EMPTY_UPDATE_STATE;
		const controller = createUpdateController(deps, (s) => {
			state = s;
		});
		await controller.check();
		await controller.apply();
		expect(deps.apply).toHaveBeenCalledWith(["cli", "companion"], "op");
		expect(deps.relaunch).toHaveBeenCalledOnce();
		expect(deps.inspect).toHaveBeenCalledTimes(1);
		expect(state.restarting).toBe(true);
		controller.dispose();
	});

	it("keeps the failure visible and logs after a failed upgrade", async () => {
		const deps = services({
			apply: async () => ({
				exitCode: 1,
				output: "Error: build failed",
				restartRequired: false,
			}),
		});
		let state = EMPTY_UPDATE_STATE;
		const controller = createUpdateController(deps, (s) => {
			state = s;
		});
		await controller.check();
		await expect(controller.apply()).resolves.toBe(false);
		expect(deps.relaunch).not.toHaveBeenCalled();
		expect(deps.inspect).toHaveBeenLastCalledWith(false);
		expect(state.error).toContain("업데이트를 완료하지 못했습니다");
		expect(state.logs).toBe("Error: build failed");
		controller.dispose();
	});

	it("does nothing when no package is outdated", async () => {
		const deps = services({ inspect: async () => current });
		const controller = createUpdateController(deps, () => {});
		await controller.check();
		await expect(controller.apply()).resolves.toBe(false);
		expect(deps.apply).not.toHaveBeenCalled();
		controller.dispose();
	});
});

describe("update panel", () => {
	it("shows installed and latest versions with one update action", () => {
		const html = render({ status: outdated });
		expect(html).toContain("설치 2.25.1 → 최신 2.26.0");
		expect(html).toContain("실행 중 2.23.0 · 설치 2.23.0 → 최신 2.24.0");
		expect(html).toContain("업데이트 있음");
		expect(html).toContain("모두 업데이트 후 재시작");
	});

	it("reports an up-to-date install without an update action", () => {
		const html = render({ status: current });
		expect(html).toContain("최신");
		expect(html).toContain("업데이트할 항목이 없습니다.");
		expect(html).not.toContain("업데이트 후 재시작");
	});

	it("points a missing CLI to Settings and explains dev builds", () => {
		const html = render({
			status: {
				...outdated,
				selfUpdateSupported: false,
				cli: { installed: null, latest: "2.26.0", outdated: false },
			},
		});
		expect(html).toContain("Homebrew 미설치");
		expect(html).toContain(
			"Settings의 설치 및 agent 연결에서 CLI를 설치하세요.",
		);
		expect(html).toContain(
			"개발 빌드에서는 Companion을 업데이트하지 않습니다.",
		);
		expect(html).not.toContain("재시작");
	});

	it("warns when Homebrew metadata could not be refreshed", () => {
		const html = render({
			status: { ...current, fetchError: "Error: network down" },
		});
		expect(html).toContain("Error: network down");
	});
});
