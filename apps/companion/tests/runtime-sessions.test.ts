import { beforeEach, describe, expect, it, vi } from "vitest";

const tauri = vi.hoisted(() => ({
	invoke: vi.fn(),
	listen: vi.fn(),
}));

vi.mock("@tauri-apps/api/core", () => ({ invoke: tauri.invoke }));
vi.mock("@tauri-apps/api/event", () => ({ listen: tauri.listen }));

import {
	EMPTY_RUNTIME_SESSIONS,
	type RuntimeSessions,
	reduceRuntimeSnapshot,
	startRuntimeSubscription,
} from "../src/application/useRuntimeSessions";
import {
	onRuntimeSnapshot,
	type RuntimeSnapshot,
	readRuntimeSnapshot,
} from "../src/infrastructure/tauriClient";

function session(state: string, observation = "observed") {
	return {
		workspace: "/tmp/task",
		provider: "claude",
		sessionId: "s1",
		agentId: "",
		turnId: "t1",
		state,
		observation,
		reason: "",
		prompt: "",
		activity: "",
		response: "",
		outcome: "",
		updatedAt: 10,
		stateChangedAt: 10,
	};
}

function document(...sessions: readonly ReturnType<typeof session>[]): string {
	return JSON.stringify({ schemaVersion: 1, sessions });
}

function snapshot(
	sequence: number,
	fields: Partial<RuntimeSnapshot> = {},
): RuntimeSnapshot {
	return {
		sequence,
		readAtMs: sequence * 1000,
		document: null,
		error: null,
		...fields,
	};
}

describe("reduceRuntimeSnapshot", () => {
	it("parses the runtime document into sessions", () => {
		const next = reduceRuntimeSnapshot(
			EMPTY_RUNTIME_SESSIONS,
			snapshot(1, { document: document(session("running")) }),
		);
		expect(next.sequence).toBe(1);
		expect(next.error).toBeUndefined();
		expect(next.sessions.map((s) => s.state)).toEqual(["running"]);
	});

	it("ignores a snapshot older than the one already applied", () => {
		const current = reduceRuntimeSnapshot(
			EMPTY_RUNTIME_SESSIONS,
			snapshot(2, { document: document(session("waiting")) }),
		);
		const next = reduceRuntimeSnapshot(
			current,
			snapshot(1, { document: document(session("running")) }),
		);
		expect(next).toBe(current);
	});

	it("keeps the previous sessions as uncertain when the read failed", () => {
		const current = reduceRuntimeSnapshot(
			EMPTY_RUNTIME_SESSIONS,
			snapshot(1, { document: document(session("running")) }),
		);
		const next = reduceRuntimeSnapshot(
			current,
			snapshot(2, { error: "collector missing" }),
		);
		expect(next.error).toBeInstanceOf(Error);
		expect(String(next.error)).toContain("collector missing");
		expect(next.sessions.map((s) => s.observation)).toEqual(["uncertain"]);
	});

	it("treats a document outside the contract as an error", () => {
		const current = reduceRuntimeSnapshot(
			EMPTY_RUNTIME_SESSIONS,
			snapshot(1, { document: document(session("running")) }),
		);
		const next = reduceRuntimeSnapshot(
			current,
			snapshot(2, { document: JSON.stringify({ schemaVersion: 9 }) }),
		);
		expect(String(next.error)).toMatch(/incompatible snapshot/);
		expect(next.sessions.map((s) => s.observation)).toEqual(["uncertain"]);
	});
});

describe("startRuntimeSubscription", () => {
	it("listens before reading so no push is lost, then applies both", async () => {
		const calls: string[] = [];
		let push: (value: RuntimeSnapshot) => void = () => undefined;
		const states: number[] = [];
		const stop = await startRuntimeSubscription({
			listen: async (callback) => {
				calls.push("listen");
				push = callback;
				return () => calls.push("unlisten");
			},
			read: async () => {
				calls.push("read");
				return snapshot(1, { document: document(session("running")) });
			},
			onState: (state) => states.push(state.sequence),
		});
		push(snapshot(2, { document: document(session("waiting")) }));
		expect(calls).toEqual(["listen", "read"]);
		expect(states).toEqual([1, 2]);
		stop();
		expect(calls).toEqual(["listen", "read", "unlisten"]);
	});

	it("drops a read result that is older than a push already applied", async () => {
		const states: number[] = [];
		await startRuntimeSubscription({
			listen: async (callback) => {
				callback(snapshot(5, { document: document(session("waiting")) }));
				return () => undefined;
			},
			read: async () => snapshot(4, { document: document(session("running")) }),
			onState: (state) => states.push(state.sequence),
		});
		expect(states).toEqual([5]);
	});

	it("waits for the first push when nothing was read yet", async () => {
		const states: number[] = [];
		await startRuntimeSubscription({
			listen: async () => () => undefined,
			read: async () => null,
			onState: (state) => states.push(state.sequence),
		});
		expect(states).toEqual([]);
	});

	it("keeps listening when the first read fails, and reports the error", async () => {
		let push: (value: RuntimeSnapshot) => void = () => undefined;
		let listening = true;
		const states: RuntimeSessions[] = [];
		const failure = new Error("runtime_snapshot unavailable");
		await startRuntimeSubscription({
			listen: async (callback) => {
				push = callback;
				return () => {
					listening = false;
				};
			},
			read: async () => {
				throw failure;
			},
			onState: (state) => states.push(state),
		});
		expect(listening).toBe(true);
		expect(states.map((state) => state.error)).toEqual([failure]);
		// The service's next push brings the window back.
		push(snapshot(1, { document: document(session("running")) }));
		expect(states.at(-1)).toMatchObject({ sequence: 1, error: undefined });
	});

	it("stops delivering once stopped", async () => {
		let push: (value: RuntimeSnapshot) => void = () => undefined;
		const states: number[] = [];
		const stop = await startRuntimeSubscription({
			listen: async (callback) => {
				push = callback;
				return () => undefined;
			},
			read: async () => null,
			onState: (state) => states.push(state.sequence),
		});
		stop();
		push(snapshot(1, { document: document(session("running")) }));
		expect(states).toEqual([]);
	});
});

describe("runtime snapshot transport", () => {
	beforeEach(() => {
		tauri.invoke.mockReset();
		tauri.listen.mockReset();
	});

	it("reads the latest snapshot from the runtime service", async () => {
		tauri.invoke.mockResolvedValue(snapshot(3, { document: "{}" }));
		await expect(readRuntimeSnapshot()).resolves.toMatchObject({
			sequence: 3,
		});
		expect(tauri.invoke).toHaveBeenCalledWith("runtime_snapshot");
	});

	it("reads no snapshot before the first read finished", async () => {
		tauri.invoke.mockResolvedValue(null);
		await expect(readRuntimeSnapshot()).resolves.toBeNull();
	});

	it("rejects a payload outside the snapshot shape", async () => {
		tauri.invoke.mockResolvedValue({ sequence: "1" });
		await expect(readRuntimeSnapshot()).rejects.toThrow(/runtime snapshot/);
	});

	it("forwards the runtime-snapshot payload", async () => {
		const received: number[] = [];
		tauri.listen.mockImplementation((name, callback) => {
			expect(name).toBe("runtime-snapshot");
			callback({ payload: snapshot(7, { error: "x" }) });
			return Promise.resolve(() => undefined);
		});
		await onRuntimeSnapshot((value) => received.push(value.sequence));
		expect(received).toEqual([7]);
	});
});
