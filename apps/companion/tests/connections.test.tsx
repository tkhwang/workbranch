import { renderToStaticMarkup } from "react-dom/server";
import { expect, it, vi } from "vitest";
import {
	createConnectionController,
	type SetupStatus,
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
