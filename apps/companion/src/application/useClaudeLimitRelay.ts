import { isTauri } from "@tauri-apps/api/core";
import { useCallback, useEffect, useState } from "react";
import {
	type ClaudeLimitRelayStatus,
	readClaudeLimitRelay,
	setClaudeLimitRelay,
} from "../infrastructure/tauriClient";

export type ClaudeLimitRelayState = {
	readonly status: ClaudeLimitRelayStatus | undefined;
	readonly loading: boolean;
	readonly update: (enabled: boolean) => Promise<void>;
};

type Options = {
	readonly onError: (error: unknown) => void;
	readonly onStatus: (status: string) => void;
};

/**
 * Reads the relay state from Claude's settings each time Settings opens, so a
 * status line changed outside the companion shows up as off.
 */
export function useClaudeLimitRelay(
	active: boolean,
	{ onError, onStatus }: Options,
): ClaudeLimitRelayState {
	const [status, setStatus] = useState<ClaudeLimitRelayStatus>();
	const [loading, setLoading] = useState(false);
	const tauriRuntimeAvailable = isTauri();

	useEffect(() => {
		if (!active || !tauriRuntimeAvailable) return;
		let cancelled = false;
		setLoading(true);
		readClaudeLimitRelay()
			.then((next) => {
				if (!cancelled) setStatus(next);
			})
			.catch((error: unknown) => {
				if (!cancelled) onError(error);
			})
			.finally(() => {
				if (!cancelled) setLoading(false);
			});
		return () => {
			cancelled = true;
		};
	}, [active, onError, tauriRuntimeAvailable]);

	const update = useCallback(
		async (enabled: boolean) => {
			if (!tauriRuntimeAvailable) {
				onStatus("Tauri runtime unavailable");
				return;
			}
			setLoading(true);
			try {
				const next = await setClaudeLimitRelay(enabled);
				setStatus(next);
				onStatus(
					next.enabled
						? "Live Claude limits enabled"
						: "Live Claude limits disabled",
				);
			} catch (error) {
				onError(error);
			} finally {
				setLoading(false);
			}
		},
		[onError, onStatus, tauriRuntimeAvailable],
	);

	return { status, loading, update };
}
