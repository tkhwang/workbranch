// Agent sessions as pushed by the Rust runtime service (src-tauri/src/
// runtime_service.rs). Every window subscribes here instead of running the
// CLI itself, so hidden windows never need a timer to stay current.
import { useEffect, useRef, useState } from "react";
import type { AgentSession } from "../domain/model";
import { parseRuntimeDocument } from "../infrastructure/parseContract";
import {
	onRuntimeSnapshot,
	type RuntimeSnapshot,
	readRuntimeSnapshot,
} from "../infrastructure/tauriClient";

export type RuntimeSessions = {
	readonly sessions: readonly AgentSession[];
	/** Why the latest read failed; the sessions are then the last good ones. */
	readonly error: unknown;
	/** The service's read counter, so a late reply never overwrites a newer push. */
	readonly sequence: number;
};

export const EMPTY_RUNTIME_SESSIONS: RuntimeSessions = {
	sessions: [],
	error: undefined,
	sequence: 0,
};

function asUncertain(
	sessions: readonly AgentSession[],
): readonly AgentSession[] {
	return sessions.map((session) => ({ ...session, observation: "uncertain" }));
}

export function reduceRuntimeSnapshot(
	current: RuntimeSessions,
	snapshot: RuntimeSnapshot,
): RuntimeSessions {
	if (snapshot.sequence <= current.sequence) return current;
	const failed = (error: unknown): RuntimeSessions => ({
		sessions: asUncertain(current.sessions),
		error,
		sequence: snapshot.sequence,
	});
	if (snapshot.document === null)
		return failed(new Error(snapshot.error ?? "Runtime read failed"));
	try {
		return {
			sessions: parseRuntimeDocument(snapshot.document),
			error: undefined,
			sequence: snapshot.sequence,
		};
	} catch (error) {
		return failed(error);
	}
}

export type RuntimeSubscriptionDeps = {
	readonly listen: (
		callback: (snapshot: RuntimeSnapshot) => void,
	) => Promise<() => void>;
	readonly read: () => Promise<RuntimeSnapshot | null>;
	readonly onState: (state: RuntimeSessions) => void;
	/** What the window already shows, so a failed first read keeps it. */
	readonly initial?: RuntimeSessions;
};

/**
 * Listens before reading, so a push that lands between the two is not lost;
 * the sequence check drops whichever of the two arrives stale. A failed read
 * becomes the state's error and the listener stays, so the service's next
 * push brings the window back.
 */
export async function startRuntimeSubscription(
	deps: RuntimeSubscriptionDeps,
): Promise<() => void> {
	let state = deps.initial ?? EMPTY_RUNTIME_SESSIONS;
	let stopped = false;
	const apply = (snapshot: RuntimeSnapshot) => {
		if (stopped) return;
		const next = reduceRuntimeSnapshot(state, snapshot);
		if (next === state) return;
		state = next;
		deps.onState(next);
	};
	const unlisten = await deps.listen(apply);
	try {
		const latest = await deps.read();
		if (latest !== null) apply(latest);
	} catch (error) {
		state = { ...state, error };
		deps.onState(state);
	}
	return () => {
		stopped = true;
		unlisten();
	};
}

/**
 * Sessions for this window while `enabled`. Turning it off keeps the last
 * sessions on screen and drops the error, as the old polling loop did.
 */
export function useRuntimeSessions(enabled: boolean): RuntimeSessions {
	const [state, setState] = useState(EMPTY_RUNTIME_SESSIONS);
	const shown = useRef(state);
	shown.current = state;
	useEffect(() => {
		if (!enabled) {
			setState((previous) =>
				previous.error === undefined
					? previous
					: { ...previous, error: undefined },
			);
			return;
		}
		let stop: (() => void) | undefined;
		let cancelled = false;
		void startRuntimeSubscription({
			listen: onRuntimeSnapshot,
			read: readRuntimeSnapshot,
			onState: setState,
			initial: shown.current,
		})
			.then((unsubscribe) => {
				if (cancelled) unsubscribe();
				else stop = unsubscribe;
			})
			.catch((error: unknown) =>
				setState((previous) => ({ ...previous, error })),
			);
		return () => {
			cancelled = true;
			stop?.();
		};
	}, [enabled]);
	return state;
}
