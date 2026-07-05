import { beforeEach, describe, expect, it, vi } from "vitest";

const tauri = vi.hoisted(() => ({
	invoke: vi.fn(),
	listen: vi.fn(),
}));

vi.mock("@tauri-apps/api/core", () => ({ invoke: tauri.invoke }));
vi.mock("@tauri-apps/api/event", () => ({ listen: tauri.listen }));

import {
	appendActivityEvents,
	CompanionActionError,
	ensureRunSucceeded,
	quitCompanion,
	readActivityEvents,
	runAction,
} from "../src/infrastructure/tauriClient";

describe("appendActivityEvents", () => {
	beforeEach(() => {
		tauri.invoke.mockReset();
	});

	it("invokes the Tauri activity append command with event payloads", async () => {
		tauri.invoke.mockResolvedValue(undefined);

		await appendActivityEvents([
			{
				v: 1,
				editedAt: 20,
				observedAt: 100,
				root: "/tmp/workbranch",
				project: "workbranch",
				task: "feat-login",
				plan: "Backend",
				planIndex: 0,
				planTitle: "Backend",
				planStatus: "in-progress",
				status: "in-progress",
				taskProgressDone: 1,
				taskProgressTotal: 2,
				progressDone: 1,
				progressTotal: 2,
				items: [{ text: "Run verification", checked: false, depth: 1 }],
			},
		]);

		expect(tauri.invoke).toHaveBeenCalledWith("append_activity_events", {
			events: [
				expect.objectContaining({
					editedAt: 20,
					planTitle: "Backend",
				}),
			],
		});
	});
});

describe("readActivityEvents", () => {
	beforeEach(() => {
		tauri.invoke.mockReset();
	});

	it("invokes the Tauri activity read command and filters invalid rows", async () => {
		tauri.invoke.mockResolvedValue([
			{ observedAt: 100, root: "/r", project: "workbranch", task: "feat-x" },
			{ observedAt: 200, project: "missing-root", task: "bad" },
		]);

		await expect(readActivityEvents(0, 300)).resolves.toEqual([
			{ observedAt: 100, root: "/r", project: "workbranch", task: "feat-x" },
		]);
		expect(tauri.invoke).toHaveBeenCalledWith("read_activity_events", {
			fromEpoch: 0,
			toEpoch: 300,
		});
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
