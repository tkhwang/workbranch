import { isTauri } from "@tauri-apps/api/core";
import { disable, enable, isEnabled } from "@tauri-apps/plugin-autostart";
import { useCallback, useEffect, useState } from "react";
import {
	type CompanionPreferenceStore,
	type CompanionPreferences,
	DEFAULT_COMPANION_PREFERENCES,
	loadCompanionPreferenceStore,
	readCompanionPreferences,
	writeCompanionPreferences,
} from "./preferences";

export type CompanionSettingsState = {
	readonly preferences: CompanionPreferences;
	readonly launchAtLogin: boolean;
	readonly launchAtLoginLoading: boolean;
	readonly updateLaunchAtLogin: (enabled: boolean) => Promise<void>;
	readonly updatePreferences: (
		preferences: CompanionPreferences,
	) => Promise<void>;
};

type CompanionSettingsOptions = {
	readonly onError: (error: unknown) => void;
	readonly onStatus: (status: string) => void;
};

export function useCompanionSettings({
	onError,
	onStatus,
}: CompanionSettingsOptions): CompanionSettingsState {
	const [preferences, setPreferences] = useState<CompanionPreferences>(
		DEFAULT_COMPANION_PREFERENCES,
	);
	const [preferenceStore, setPreferenceStore] =
		useState<CompanionPreferenceStore>();
	const [launchAtLogin, setLaunchAtLogin] = useState(false);
	const [launchAtLoginLoading, setLaunchAtLoginLoading] = useState(true);
	const tauriRuntimeAvailable = isTauri();

	useEffect(() => {
		if (!tauriRuntimeAvailable) {
			return;
		}
		let cancelled = false;
		async function loadPreferences(): Promise<void> {
			try {
				const store = await loadCompanionPreferenceStore();
				const result = await readCompanionPreferences(store);
				if (cancelled) {
					return;
				}
				setPreferenceStore(store);
				setPreferences(result.preferences);
				if (result.sanitized) {
					onStatus("Preferences reset to supported defaults");
					await writeCompanionPreferences(store, result.preferences);
				}
			} catch (error) {
				if (!cancelled) {
					onError(error);
				}
			}
		}
		void loadPreferences();
		return () => {
			cancelled = true;
		};
	}, [onError, onStatus, tauriRuntimeAvailable]);

	useEffect(() => {
		if (!tauriRuntimeAvailable) {
			setLaunchAtLoginLoading(false);
			return;
		}
		let cancelled = false;
		async function loadLaunchAtLogin(): Promise<void> {
			try {
				const enabled = await isEnabled();
				if (!cancelled) {
					setLaunchAtLogin(enabled);
				}
			} catch (error) {
				if (!cancelled) {
					onError(error);
				}
			} finally {
				if (!cancelled) {
					setLaunchAtLoginLoading(false);
				}
			}
		}
		void loadLaunchAtLogin();
		return () => {
			cancelled = true;
		};
	}, [onError, tauriRuntimeAvailable]);

	const updatePreferences = useCallback(
		async (next: CompanionPreferences) => {
			if (!tauriRuntimeAvailable) {
				onStatus("Tauri runtime unavailable");
				return;
			}
			const previous = preferences;
			setPreferences(next);
			try {
				const store = preferenceStore ?? (await loadCompanionPreferenceStore());
				setPreferenceStore(store);
				await writeCompanionPreferences(store, next);
				onStatus("Preferences updated");
			} catch (error) {
				setPreferences(previous);
				onError(error);
			}
		},
		[onError, onStatus, preferenceStore, preferences, tauriRuntimeAvailable],
	);

	const updateLaunchAtLogin = useCallback(
		async (enabled: boolean) => {
			if (!tauriRuntimeAvailable) {
				onStatus("Tauri runtime unavailable");
				return;
			}
			setLaunchAtLoginLoading(true);
			try {
				if (enabled) {
					await enable();
				} else {
					await disable();
				}
				const current = await isEnabled();
				setLaunchAtLogin(current);
				onStatus(
					current ? "Launch at login enabled" : "Launch at login disabled",
				);
			} catch (error) {
				onError(error);
			} finally {
				setLaunchAtLoginLoading(false);
			}
		},
		[onError, onStatus, tauriRuntimeAvailable],
	);

	return {
		preferences,
		launchAtLogin,
		launchAtLoginLoading,
		updateLaunchAtLogin,
		updatePreferences,
	};
}
