import { isTauri } from "@tauri-apps/api/core";
import { useCallback, useEffect, useState } from "react";
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
	const tauriRuntimeAvailable = isTauri();

	useEffect(() => {
		if (!active || !tauriRuntimeAvailable) return;
		let cancelled = false;
		let stop: (() => void) | undefined;
		const read = () => {
			setLoading(true);
			readIdeWindowAccess()
				.then((access) => {
					if (!cancelled) setGranted(access.granted);
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
	}, [active, onError, tauriRuntimeAvailable]);

	const request = useCallback(async () => {
		if (!tauriRuntimeAvailable) {
			onStatus("Tauri runtime unavailable");
			return;
		}
		try {
			const access = await requestIdeWindowAccess();
			setGranted(access.granted);
		} catch (error) {
			onError(error);
		}
	}, [onError, onStatus, tauriRuntimeAvailable]);

	const openSettings = useCallback(async () => {
		if (!tauriRuntimeAvailable) {
			onStatus("Tauri runtime unavailable");
			return;
		}
		await openIdeWindowAccessSettings().catch(onError);
	}, [onError, onStatus, tauriRuntimeAvailable]);

	return { granted, loading, request, openSettings };
}
