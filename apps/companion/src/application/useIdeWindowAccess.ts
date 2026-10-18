import { isTauri } from "@tauri-apps/api/core";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
	onWindowFocused,
	openIdeWindowAccessSettings,
	readIdeWindowAccess,
	requestIdeWindowAccess,
} from "../infrastructure/tauriClient";

export type IdeWindowAccessState = {
	/** `undefined` until the first read comes back. */
	readonly granted: boolean | undefined;
	readonly loading: boolean;
	readonly request: () => Promise<void>;
	readonly openSettings: () => Promise<void>;
};

type Options = {
	readonly onError: (error: unknown) => void;
	readonly onStatus: (status: string) => void;
};

export type AccessAnswers = {
	/** Call as a read starts; the returned function applies its answer. */
	readonly read: () => (granted: boolean) => void;
	/** Applies a request's answer and outdates the reads still running. */
	readonly request: (granted: boolean) => void;
};

/**
 * Tauri does not order the answers of separate calls, so a read that
 * started before a request can answer after it with the older state. Such a
 * read is dropped.
 */
export function accessAnswers(
	apply: (granted: boolean) => void,
): AccessAnswers {
	let generation = 0;
	return {
		read: () => {
			const started = generation;
			return (granted) => {
				if (started === generation) apply(granted);
			};
		},
		request: (granted) => {
			generation += 1;
			apply(granted);
		},
	};
}

/**
 * Reads the Accessibility permission each time Settings opens and each time
 * the window comes back, because it is granted in System Settings, outside
 * the app.
 */
export function useIdeWindowAccess(
	active: boolean,
	{ onError, onStatus }: Options,
): IdeWindowAccessState {
	const [granted, setGranted] = useState<boolean>();
	const [loading, setLoading] = useState(false);
	const answers = useMemo(() => accessAnswers(setGranted), []);
	const tauriRuntimeAvailable = isTauri();

	useEffect(() => {
		if (!active || !tauriRuntimeAvailable) return;
		let cancelled = false;
		let stop: (() => void) | undefined;
		const read = () => {
			const answer = answers.read();
			setLoading(true);
			readIdeWindowAccess()
				.then((access) => {
					if (!cancelled) answer(access.granted);
				})
				.catch((error: unknown) => {
					if (!cancelled) onError(error);
				})
				.finally(() => {
					if (!cancelled) setLoading(false);
				});
		};
		read();
		void onWindowFocused(read).then((unlisten) => {
			if (cancelled) unlisten();
			else stop = unlisten;
		});
		return () => {
			cancelled = true;
			stop?.();
		};
	}, [active, answers, onError, tauriRuntimeAvailable]);

	const request = useCallback(async () => {
		if (!tauriRuntimeAvailable) {
			onStatus("Tauri runtime unavailable");
			return;
		}
		try {
			const access = await requestIdeWindowAccess();
			answers.request(access.granted);
		} catch (error) {
			onError(error);
		}
	}, [answers, onError, onStatus, tauriRuntimeAvailable]);

	const openSettings = useCallback(async () => {
		if (!tauriRuntimeAvailable) {
			onStatus("Tauri runtime unavailable");
			return;
		}
		await openIdeWindowAccessSettings().catch(onError);
	}, [onError, onStatus, tauriRuntimeAvailable]);

	return { granted, loading, request, openSettings };
}
