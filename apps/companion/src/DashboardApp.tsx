// The dashboard window's composition root (COMP001). It shows what the menu
// bar board shows, from the same sources: runtime pushes from the Rust
// service and the event-driven workspace list.
import { isTauri } from "@tauri-apps/api/core";
import { getCurrentWebviewWindow } from "@tauri-apps/api/webviewWindow";
import { useEffect, useMemo, useRef, useState } from "react";
import { buildDashboardModel } from "./application/dashboard";
import {
	DEFAULT_COMPANION_PREFERENCES,
	loadCompanionPreferenceStore,
	readCompanionPreferences,
} from "./application/preferences";
import { useRuntimeSessions } from "./application/useRuntimeSessions";
import type { GlobalState } from "./domain/model";
import {
	onRootChanged,
	readScreensaverStatus,
	refreshRoot,
	refreshStatus,
} from "./infrastructure/tauriClient";
import { startWorkspaceMonitor } from "./infrastructure/workspaceMonitor";
import { DASHBOARD_CARDS_PER_COLUMN, Dashboard } from "./ui/Dashboard";

/** Mirrors the preview label prefix in src-tauri/src/screensaver/windows.rs. */
const PREVIEW_LABEL_PREFIX = "dashboard-preview-";
const LIST_HEARTBEAT_MS = 5 * 60 * 1000;
const EMPTY_STATE: GlobalState = { projects: [], errors: [] };

function useNow(): Date {
	const [now, setNow] = useState(() => new Date());
	useEffect(() => {
		const timer = window.setInterval(() => setNow(new Date()), 1000);
		return () => window.clearInterval(timer);
	}, []);
	return now;
}

export function DashboardApp() {
	const tauriAvailable = isTauri();
	const [preview] = useState(
		() =>
			tauriAvailable &&
			getCurrentWebviewWindow().label.startsWith(PREVIEW_LABEL_PREFIX),
	);
	const [state, setState] = useState<GlobalState>(EMPTY_STATE);
	const stateRef = useRef<GlobalState>(EMPTY_STATE);
	const [preferences, setPreferences] = useState(DEFAULT_COMPANION_PREFERENCES);
	// Unknown counts as unavailable: never promise a lock that may not come.
	const [lockAvailable, setLockAvailable] = useState(false);
	const runtime = useRuntimeSessions(tauriAvailable);
	const now = useNow();

	useEffect(() => {
		if (!tauriAvailable) return;
		let cancelled = false;
		void readScreensaverStatus()
			.then((status) => {
				if (!cancelled) setLockAvailable(status.lockAvailable);
			})
			.catch(() => undefined);
		return () => {
			cancelled = true;
		};
	}, [tauriAvailable]);

	useEffect(() => {
		if (!tauriAvailable) return;
		let cancelled = false;
		void loadCompanionPreferenceStore()
			.then(readCompanionPreferences)
			.then((result) => {
				if (!cancelled) setPreferences(result.preferences);
			})
			// Defaults are a fine look for a dashboard nobody can interact with.
			.catch(() => undefined);
		return () => {
			cancelled = true;
		};
	}, [tauriAvailable]);

	useEffect(() => {
		if (!tauriAvailable) return;
		let stop: (() => void) | undefined;
		let cancelled = false;
		void startWorkspaceMonitor({
			refresh: refreshStatus,
			refreshRoot,
			getState: () => stateRef.current,
			onState: (next) => {
				stateRef.current = next;
				setState(next);
			},
			// A failed refresh keeps the last good list on screen.
			onError: () => undefined,
			// The main window owns watcher registration; this one only listens.
			watchRoots: async () => undefined,
			onRootChanged,
			heartbeatMs: LIST_HEARTBEAT_MS,
		})
			.then((monitor) => {
				if (cancelled) monitor.stop();
				else stop = monitor.stop;
			})
			.catch(() => undefined);
		return () => {
			cancelled = true;
			stop?.();
		};
	}, [tauriAvailable]);

	const model = useMemo(
		() =>
			buildDashboardModel(state, runtime.sessions, DASHBOARD_CARDS_PER_COLUMN),
		[state, runtime.sessions],
	);
	return (
		<Dashboard
			font={preferences.font}
			lockAvailable={lockAvailable}
			model={model}
			now={now}
			preview={preview}
			theme={preferences.theme}
		/>
	);
}
