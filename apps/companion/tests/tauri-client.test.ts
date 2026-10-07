import { beforeEach, describe, expect, it, vi } from "vitest";

const tauri = vi.hoisted(() => ({
	invoke: vi.fn(),
	listen: vi.fn(),
}));

vi.mock("@tauri-apps/api/core", () => ({ invoke: tauri.invoke }));
vi.mock("@tauri-apps/api/event", () => ({ listen: tauri.listen }));

import {
	applyUpdates,
	CompanionActionError,
	checkUpdates,
	ensureRunSucceeded,
	onRootChanged,
	onWindowFocused,
	quitCompanion,
	readUsageSnapshot,
	refreshRoot,
	runAction,
} from "../src/infrastructure/tauriClient";

describe("root refresh", () => {
	beforeEach(() => {
		tauri.invoke.mockReset();
		tauri.listen.mockReset();
	});

	it("maps one local list document through the existing project ACL", async () => {
		tauri.invoke.mockResolvedValue(
			JSON.stringify({
				schemaVersion: 2,
				project: "workbranch",
				root: "/tmp/workbranch",
				tasks: [],
			}),
		);

		await expect(refreshRoot("/tmp/workbranch")).resolves.toMatchObject({
			name: "workbranch",
			root: "/tmp/workbranch",
		});
		expect(tauri.invoke).toHaveBeenCalledWith("workbranch_list", {
			root: "/tmp/workbranch",
		});
	});

	it("forwards the roots-changed payload instead of the Tauri event object", async () => {
		let changedRoot = "";
		tauri.listen.mockImplementation((_name, callback) => {
			callback({ payload: "/tmp/workbranch" });
			return Promise.resolve(() => undefined);
		});

		await onRootChanged((root) => {
			changedRoot = root;
		});

		expect(changedRoot).toBe("/tmp/workbranch");
	});
});

describe("readUsageSnapshot", () => {
	beforeEach(() => {
		tauri.invoke.mockReset();
	});

	const provider = {
		available: true,
		limits: {
			observedAt: 100,
			plan: "pro",
			windows: [{ windowMinutes: 10080, usedPercent: 32, resetsAt: 900 }],
		},
		buckets: [{ start: 0, input: 1, output: 2, cacheRead: 3, cacheWrite: 4 }],
		errors: [],
	};

	it("asks Rust for the requested day span and keeps the validated payload", async () => {
		tauri.invoke.mockResolvedValue({
			generatedAt: 200,
			since: 0,
			claude: { ...provider, limits: null },
			codex: provider,
		});

		const snapshot = await readUsageSnapshot(14);

		expect(tauri.invoke).toHaveBeenCalledWith("usage_snapshot", { days: 14 });
		expect(snapshot.claude.limits).toBeNull();
		expect(snapshot.codex.limits?.windows[0]?.resetsAt).toBe(900);
		expect(snapshot.codex.buckets[0]?.cacheWrite).toBe(4);
	});

	it("rejects a payload with a malformed bucket instead of drawing it", async () => {
		tauri.invoke.mockResolvedValue({
			generatedAt: 200,
			since: 0,
			claude: provider,
			codex: { ...provider, buckets: [{ start: 0, input: -1 }] },
		});

		await expect(readUsageSnapshot(14)).rejects.toThrow(
			/Invalid usage snapshot/,
		);
	});
});

describe("ensureRunSucceeded", () => {
	it("throws stderr when a delegated CLI action exits nonzero", () => {
		expect(() =>
			ensureRunSucceeded({
				exit_code: 127,
				stdout: "",
				stderr: "configured IDE command not found: code",
			}),
		).toThrow(CompanionActionError);
	});
});

describe("quitCompanion", () => {
	beforeEach(() => {
		tauri.invoke.mockReset();
	});

	it("invokes the Tauri quit command", async () => {
		tauri.invoke.mockResolvedValue(undefined);

		await quitCompanion();

		expect(tauri.invoke).toHaveBeenCalledWith("quit_app");
	});
});

describe("runAction", () => {
	beforeEach(() => {
		tauri.invoke.mockReset();
	});

	it("rejects when the delegated CLI action exits nonzero", async () => {
		tauri.invoke.mockResolvedValue({
			exit_code: 2,
			stdout: "",
			stderr: "task not found: missing-task",
		});

		await expect(
			runAction({ kind: "terminal", task: "missing-task" }, "/tmp/workbranch"),
		).rejects.toThrow("task not found: missing-task");
	});
});

describe("runtime compatibility errors", () => {
	it("replaces an old CLI usage dump with one actionable message", async () => {
		const { companionErrorMessage, isCliCompatibilityError } = await import(
			"../src/infrastructure/tauriClient"
		);
		const failure =
			"command failed with exit 1: Usage: workbranch <command> [args] " +
			"Workspace: list add done ".repeat(100) +
			"[-] Error: unknown command: runtime";
		expect(isCliCompatibilityError(failure)).toBe(true);
		expect(companionErrorMessage(failure)).toContain("CLI");
		expect(companionErrorMessage(failure)).not.toContain("Usage:");
		expect(companionErrorMessage(failure).length).toBeLessThan(180);
	});
	it("preserves actionable collector-missing guidance", async () => {
		const { companionErrorMessage } = await import(
			"../src/infrastructure/tauriClient"
		);
		expect(
			companionErrorMessage(
				"Install/update the workbranch runtime collector (workbranch-agent-runtime missing)",
			),
		).toContain("수집기");
	});
});

describe("updates", () => {
	beforeEach(() => {
		tauri.invoke.mockReset();
	});

	it("invokes the allowlisted update commands", async () => {
		tauri.invoke.mockResolvedValue({});

		await checkUpdates(true);
		await applyUpdates(["cli", "companion"], "op-1");

		expect(tauri.invoke).toHaveBeenNthCalledWith(1, "update_check", {
			fetch: true,
		});
		expect(tauri.invoke).toHaveBeenNthCalledWith(2, "update_apply", {
			targets: ["cli", "companion"],
			operationId: "op-1",
		});
	});
});

describe("onWindowFocused", () => {
	it("listens for the native window focus event", async () => {
		let focused = 0;
		tauri.listen.mockReset();
		tauri.listen.mockImplementation((_name, callback) => {
			callback({ payload: null });
			return Promise.resolve(() => undefined);
		});

		await onWindowFocused(() => {
			focused += 1;
		});

		expect(tauri.listen).toHaveBeenCalledWith(
			"tauri://focus",
			expect.any(Function),
		);
		expect(focused).toBe(1);
	});
});
