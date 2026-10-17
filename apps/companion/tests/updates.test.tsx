import { Children, isValidElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import {
	type ConnectionState,
	EMPTY_CONNECTION_STATE,
} from "../src/application/connections";
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
import { StatusSettings } from "../src/ui/StatusSettings";

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

function render(
	state: Partial<UpdateState>,
	connections: ConnectionState = EMPTY_CONNECTION_STATE,
) {
	return renderToStaticMarkup(
		<StatusSettings
			connections={connections}
			onApplyUpdates={() => {}}
			onCheckUpdates={() => {}}
			onOpenConnections={() => {}}
			updates={{ ...EMPTY_UPDATE_STATE, ...state }}
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

describe("settings status", () => {
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
		expect(html).toContain("Connections에서 CLI를 설치하세요.");
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

	it("shows progress on the button that started the work", () => {
		const checking = render({ status: outdated, checking: true });
		expect(checking.match(/aria-busy="true"/g)).toHaveLength(1);
		expect(checking).toMatch(/aria-busy="true"[^>]*>.*확인 중…<\/button>/);
		const updating = render({ status: outdated, updating: true });
		expect(updating.match(/aria-busy="true"/g)).toHaveLength(1);
		expect(updating).toMatch(/aria-busy="true"[^>]*>.*업데이트 중…<\/button>/);
		expect(updating).not.toContain("모두 업데이트 후 재시작");
	});
	it("asks for the first check instead of running brew update on open", () => {
		const html = render({});
		expect(html).toMatch(/<button[^>]*>업데이트 확인<\/button>/);
		expect(html).toContain(
			"Homebrew로 설치한 CLI와 Companion의 최신 버전을 확인합니다.",
		);
		expect(html).not.toContain("업데이트 있음");
	});

	it("puts available updates first with the one button that applies them", () => {
		const html = render({ status: outdated });
		expect(html.indexOf("업데이트 있음 · CLI, Companion")).toBeLessThan(
			html.indexOf("Workbranch CLI"),
		);
		expect(html.match(/모두 업데이트 후 재시작/g)).toHaveLength(1);
	});

	it("orders the check outcome, CLI then Companion, the log, then agents", () => {
		const idle = render({ status: current });
		expect(idle.indexOf("업데이트할 항목이 없습니다.")).toBeLessThan(
			idle.indexOf("<strong>Workbranch CLI</strong>"),
		);
		const failed = render({
			status: outdated,
			error: "업데이트를 완료하지 못했습니다.",
			logs: "brew upgrade log",
		});
		const positions = [
			"업데이트를 완료하지 못했습니다.",
			"<strong>Workbranch CLI</strong>",
			"<strong>Workbranch Companion</strong>",
			"brew upgrade log",
			"<strong>Agent 연결</strong>",
		].map((text) => failed.indexOf(text));
		expect(positions.every((index) => index >= 0)).toBe(true);
		expect(positions).toEqual([...positions].sort((a, b) => a - b));
	});

	it("summarizes CLI and agent readiness with a way to Connections", () => {
		const html = render(
			{ status: current },
			{
				...EMPTY_CONNECTION_STATE,
				loading: false,
				status: {
					brewPath: "/opt/homebrew/bin/brew",
					formulaInstalled: true,
					cli: {
						state: "ready",
						path: "/opt/homebrew/bin/workbranch",
						version: "2.37.0",
						message: "CLI와 수집기를 사용할 수 있습니다.",
					},
					agents: [
						{
							provider: "claude",
							executablePath: "/bin/claude",
							state: "configured",
							lastObservedAt: 1,
							message: "설정됨",
						},
						{
							provider: "codex",
							executablePath: "/bin/codex",
							state: "disconnected",
							lastObservedAt: null,
							message: "연결 필요",
						},
					],
				},
			},
		);
		expect(html).toContain("CLI 준비됨 · Claude Code 설정됨 · Codex 미연결");

		let opened = 0;
		const element = StatusSettings({
			connections: EMPTY_CONNECTION_STATE,
			onApplyUpdates: () => {},
			onCheckUpdates: () => {},
			onOpenConnections: () => {
				opened += 1;
			},
			updates: EMPTY_UPDATE_STATE,
		});
		const buttons: { children?: ReactNode; onClick?: () => void }[] = [];
		const visit = (child: ReactNode): void => {
			if (
				!isValidElement<{ children?: ReactNode; onClick?: () => void }>(child)
			)
				return;
			if (child.type === "button") buttons.push(child.props);
			Children.forEach(child.props.children, visit);
		};
		visit(element);
		buttons.find((button) => button.children === "연결 관리")?.onClick?.();
		expect(opened).toBe(1);
	});
});
