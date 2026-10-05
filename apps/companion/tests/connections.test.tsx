import { renderToStaticMarkup } from "react-dom/server";
import { expect, it, vi } from "vitest";
import {
	type ConnectionState,
	createConnectionController,
	EMPTY_CONNECTION_STATE,
	type SetupStatus,
	sameSetupAction,
} from "../src/application/connections";
import { ConnectionsPanel } from "../src/ui/ConnectionsPanel";

const status: SetupStatus = {
	brewPath: "/opt/homebrew/bin/brew",
	formulaInstalled: false,
	cli: { state: "missing", path: null, version: "", message: "설치 필요" },
	agents: [
		{
			provider: "claude",
			executablePath: "/bin/claude",
			state: "disconnected",
			lastObservedAt: null,
			message: "연결 필요",
		},
		{
			provider: "codex",
			executablePath: null,
			state: "notInstalled",
			lastObservedAt: null,
			message: "agent 미설치",
		},
		{
			provider: "grok",
			executablePath: "/bin/grok",
			state: "configured",
			lastObservedAt: null,
			message: "trust 확인",
		},
	],
};
it("keeps CLI bootstrap available before a CLI exists", () => {
	const html = renderToStaticMarkup(
		<ConnectionsPanel
			theme="claude"
			state={{
				status,
				loading: false,
				busy: null,
				lastAction: null,
				error: null,
				logs: "",
				notice: null,
				verificationAfter: {},
			}}
			onRefresh={() => {}}
			onAction={() => {}}
		/>,
	);
	expect(html).toContain("CLI 설치");
	expect(html).toContain("Claude");
	expect(html).toContain("Codex");
	expect(html).toContain("Grok");
	expect(html).toContain("첫 이벤트");
	expect(html).not.toContain("수신 확인됨");
});
it("does not install anything while inspecting onboarding", async () => {
	const run = vi.fn();
	const inspect = vi.fn(async () => status);
	const controller = createConnectionController(
		{ inspect, run, subscribe: async () => () => {}, id: () => "op" },
		() => {},
	);
	await controller.refresh();
	expect(run).not.toHaveBeenCalled();
	controller.dispose();
});
it("serializes actions and verifies setup after installing", async () => {
	let complete: (value: {
		exit_code: number;
		stdout: string;
		stderr: string;
	}) => void = () => {};
	const run = vi.fn(
		() =>
			new Promise<{ exit_code: number; stdout: string; stderr: string }>(
				(resolve) => {
					complete = resolve;
				},
			),
	);
	const inspect = vi.fn(async () => ({
		...status,
		cli: { ...status.cli, state: "ready" as const },
	}));
	const controller = createConnectionController(
		{ inspect, run, subscribe: async () => () => {}, id: () => "op" },
		() => {},
	);
	const first = controller.run({ kind: "installCli" });
	await Promise.resolve();
	expect(await controller.run({ kind: "updateCli" })).toBe(false);
	complete({ exit_code: 0, stdout: "installed", stderr: "" });
	expect(await first).toBe(true);
	expect(run).toHaveBeenCalledTimes(1);
	expect(inspect).toHaveBeenCalledTimes(1);
	controller.dispose();
});
it("does not call an installed but incompatible CLI ready", async () => {
	const controller = createConnectionController(
		{
			inspect: async () => ({
				...status,
				cli: { ...status.cli, state: "incompatible" },
			}),
			run: async () => ({
				exit_code: 0,
				stdout: "already installed",
				stderr: "",
			}),
			subscribe: async () => () => {},
			id: () => "op",
		},
		() => {},
	);
	expect(await controller.run({ kind: "installCli" })).toBe(false);
	controller.dispose();
});

it("does not treat an old receipt as a verified new connection", async () => {
	const { receiptState, cliSetupAction } = await import(
		"../src/application/connections"
	);
	expect(receiptState(100, 200)).toBe("historical");
	expect(receiptState(201, 200)).toBe("verified");
	expect(
		cliSetupAction({
			...status,
			formulaInstalled: false,
			cli: { ...status.cli, state: "incompatible" },
		}),
	).toBe("installCli");
});

it("requires a new receipt after reconnect and validates registered state", async () => {
	const { EMPTY_CONNECTION_STATE } = await import(
		"../src/application/connections"
	);
	let current = EMPTY_CONNECTION_STATE;
	const configured = {
		...status,
		cli: { ...status.cli, state: "ready" as const },
	};
	const controller = createConnectionController(
		{
			inspect: async () => configured,
			run: async () => ({ exit_code: 0, stdout: "configured", stderr: "" }),
			subscribe: async () => () => {},
			id: () => "op",
			now: () => 200,
		},
		(state) => {
			current = state;
		},
	);
	expect(await controller.run({ kind: "connectAgent", provider: "grok" })).toBe(
		true,
	);
	expect(current.verificationAfter.grok).toBe(200);
	expect(
		await controller.run({ kind: "connectAgent", provider: "claude" }),
	).toBe(false);
	controller.dispose();
});

it("does not duplicate streamed logs in the final failure result", async () => {
	const { EMPTY_CONNECTION_STATE } = await import(
		"../src/application/connections"
	);
	let current = EMPTY_CONNECTION_STATE;
	const text = "requires confirmation; re-run with --trust";
	const controller = createConnectionController(
		{
			inspect: async () => status,
			run: async () => ({ exit_code: 1, stdout: "", stderr: text }),
			subscribe: async (_id, receive) => {
				receive(text);
				return () => {};
			},
			id: () => "op",
		},
		(value) => {
			current = value;
		},
	);
	expect(await controller.run({ kind: "connectAgent", provider: "grok" })).toBe(
		false,
	);
	expect(current.logs.split(text)).toHaveLength(2);
	expect(current.error).toContain("신뢰 승인");
	controller.dispose();
});

it("shows the exact Grok source and executable-plugin permission before approval", async () => {
	const { GrokTrustPrompt } = await import("../src/ui/ConnectionsPanel");
	const approve = vi.fn();
	const cancel = vi.fn();
	const html = renderToStaticMarkup(
		<GrokTrustPrompt
			source="/reviewed/plugin"
			disabled={false}
			onApprove={approve}
			onCancel={cancel}
		/>,
	);
	expect(html).toContain("/reviewed/plugin");
	expect(html).toContain("이 컴퓨터에서 실행");
	expect(html).toContain("신뢰하고 설치");
	expect(html).toContain("취소");
	expect(approve).not.toHaveBeenCalled();
});

const readyStatus: SetupStatus = {
	...status,
	formulaInstalled: true,
	cli: { ...status.cli, state: "ready", message: "준비됨" },
	agents: status.agents.map((agent) =>
		agent.provider === "codex"
			? {
					...agent,
					executablePath: "/bin/codex",
					state: "disconnected",
					message: "연결 필요",
				}
			: agent,
	),
};
function renderPanel(state: Partial<ConnectionState>) {
	return renderToStaticMarkup(
		<ConnectionsPanel
			theme="claude"
			state={{
				...EMPTY_CONNECTION_STATE,
				loading: false,
				status: readyStatus,
				...state,
			}}
			onRefresh={() => {}}
			onAction={() => {}}
		/>,
	);
}
function between(html: string, from: string, to: string) {
	return html.slice(
		html.indexOf(`<strong>${from}</strong>`),
		html.indexOf(`<strong>${to}</strong>`),
	);
}

it("shows progress only on the button that is running", () => {
	const action = { kind: "connectAgent", provider: "codex" } as const;
	const html = renderPanel({ busy: action, lastAction: action });
	const codex = between(html, "Codex", "Grok Build");
	expect(html.match(/aria-busy="true"/g)).toHaveLength(1);
	expect(codex).toContain('aria-busy="true"');
	expect(codex).toContain("button-spinner");
	expect(codex).toContain("연결 중…");
	// Every other action waits, without claiming to run.
	const claude = between(html, "Claude Code", "Codex");
	expect(claude).toMatch(/<button[^>]*disabled=""[^>]*>연결<\/button>/);
	expect(html).not.toContain("확인 중…");
});

it("labels running CLI steps by what they do", () => {
	expect(renderPanel({ busy: { kind: "repairCli" } })).toContain(
		"설치 복구 중…",
	);
	expect(renderPanel({ busy: { kind: "updateCli" } })).toContain(
		"CLI 업데이트 중…",
	);
	expect(renderPanel({ loading: true })).toContain("확인 중…");
});

it("puts an action result beside the button that ran it", () => {
	const html = renderPanel({
		lastAction: { kind: "connectAgent", provider: "codex" },
		error: "연결을 확인하지 못했습니다.",
	});
	expect(between(html, "Codex", "Grok Build")).toContain(
		"연결을 확인하지 못했습니다.",
	);
	expect(html.split("연결을 확인하지 못했습니다.")).toHaveLength(2);
	const cli = renderPanel({
		lastAction: { kind: "updateCli" },
		notice: "CLI와 수집기 준비가 완료됐습니다.",
	});
	expect(between(cli, "1 · Workbranch CLI", "Claude Code")).toContain(
		"CLI와 수집기 준비가 완료됐습니다.",
	);
});

it("keeps status check failures at the top of the panel", () => {
	const html = renderPanel({ error: "설치 상태를 확인하지 못했습니다." });
	expect(html.indexOf("설치 상태를 확인하지 못했습니다.")).toBeLessThan(
		html.indexOf("1 · Workbranch CLI"),
	);
});

it("remembers which action a result belongs to until a check fails", async () => {
	let current = EMPTY_CONNECTION_STATE;
	const inspect = vi.fn(async () => readyStatus);
	const controller = createConnectionController(
		{
			inspect,
			run: async () => ({ exit_code: 1, stdout: "", stderr: "failed" }),
			subscribe: async () => () => {},
			id: () => "op",
		},
		(value) => {
			current = value;
		},
	);
	expect(
		await controller.run({ kind: "connectAgent", provider: "codex" }),
	).toBe(false);
	expect(current.lastAction).toEqual({
		kind: "connectAgent",
		provider: "codex",
	});
	expect(current.error).not.toBeNull();
	inspect.mockRejectedValueOnce(new Error("offline"));
	await controller.refresh();
	expect(current.lastAction).toBeNull();
	expect(current.error).toContain("설치 상태를 확인하지 못했습니다");
	controller.dispose();
});

it("matches a running action to its button regardless of the approved source", () => {
	const grok = { kind: "connectAgent", provider: "grok" } as const;
	expect(sameSetupAction({ ...grok, approvedSource: "/reviewed" }, grok)).toBe(
		true,
	);
	expect(
		sameSetupAction(grok, { kind: "disconnectAgent", provider: "grok" }),
	).toBe(false);
	expect(sameSetupAction(grok, { ...grok, provider: "codex" })).toBe(false);
	expect(sameSetupAction({ kind: "updateCli" }, { kind: "repairCli" })).toBe(
		false,
	);
});
