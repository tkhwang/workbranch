import { useCallback, useEffect, useRef, useState } from "react";
import { USAGE_DAYS, type UsageSnapshot } from "../domain/usage";
import {
	companionErrorMessage,
	readUsageSnapshot,
} from "../infrastructure/tauriClient";

const REFRESH_INTERVAL_MS = 60 * 1000;

export type UsageState = {
	readonly snapshot: UsageSnapshot | undefined;
	readonly error: string | undefined;
};

export type UsageController = UsageState & {
	readonly refresh: () => Promise<void>;
};

/**
 * Keeps the last good snapshot on screen when a later read fails, so a
 * transient file error shows as a message instead of blanking the summary.
 */
export function useUsage(
	enabled: boolean,
	load: (days: number) => Promise<UsageSnapshot> = readUsageSnapshot,
): UsageController {
	const [state, setState] = useState<UsageState>({
		snapshot: undefined,
		error: undefined,
	});
	const loading = useRef(false);

	const refresh = useCallback(async () => {
		if (!enabled || loading.current) return;
		loading.current = true;
		try {
			const snapshot = await load(USAGE_DAYS);
			setState({ snapshot, error: undefined });
		} catch (error) {
			setState((previous) => ({
				snapshot: previous.snapshot,
				error: companionErrorMessage(error),
			}));
		} finally {
			loading.current = false;
		}
	}, [enabled, load]);

	useEffect(() => {
		if (!enabled) return;
		void refresh();
		const timer = window.setInterval(() => {
			void refresh();
		}, REFRESH_INTERVAL_MS);
		return () => window.clearInterval(timer);
	}, [enabled, refresh]);

	return { ...state, refresh };
}
