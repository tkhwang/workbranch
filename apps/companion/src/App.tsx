import { isTauri } from "@tauri-apps/api/core";
import { useCallback, useEffect, useMemo, useState } from "react";
import { createActivityRefresh } from "./application/activity";
import { resolvedCompanionTheme } from "./application/preferences";
import { buildMenuModel, type MenuModel } from "./application/state";
import { useSystemThemeMode } from "./application/systemThemeMode";
import { useCompanionSettings } from "./application/useCompanionSettings";
import type { GlobalState, Task } from "./domain/model";
import {
	appendActivityEvents,
	type CompanionCommand,
	onRootChanged,
	quitCompanion,
	refreshStatus,
	runAction,
	watchRoots,
} from "./infrastructure/tauriClient";
import { startWorkspaceMonitor } from "./infrastructure/workspaceMonitor";
import { AppSummary } from "./ui/AppSummary";
import { AppToolbar } from "./ui/AppToolbar";
import { ProjectGroup } from "./ui/ProjectGroup";
import { SettingsView } from "./ui/SettingsView";
import { StatusAlert } from "./ui/StatusAlert";
import type { TaskActionKind } from "./ui/TaskRow";
import { type CompanionView, ViewNav } from "./ui/ViewNav";

const EMPTY_STATE: GlobalState = { projects: [], errors: [] };
const TAURI_RUNTIME_UNAVAILABLE = "Tauri runtime unavailable";

function currentEpochSeconds(): number {
	return Math.floor(Date.now() / 1000);
}

function commandForTaskAction(
	task: Task,
	kind: TaskActionKind,
): CompanionCommand {
	switch (kind) {
		case "ide":
			return { kind: "ide", task: task.name };
		case "terminal":
			return { kind: "terminal", task: task.name };
		case "finder":
			return { kind: "finder", task: task.name };
	}
}

export function App() {
	const [state, setState] = useState<GlobalState>(EMPTY_STATE);
	const [status, setStatus] = useState("Ready");
	const [visibleError, setVisibleError] = useState<string>();
	const [currentView, setCurrentView] = useState<CompanionView>("main");
	const systemThemeMode = useSystemThemeMode();
	const model: MenuModel = buildMenuModel(state);
	const tauriRuntimeAvailable = isTauri();
	const refreshWithActivity = useMemo(
		() =>
			createActivityRefresh({
				refresh: refreshStatus,
				append: appendActivityEvents,
				now: currentEpochSeconds,
			}),
		[],
	);

	const showStatus = useCallback((message: string) => {
		setStatus(message);
		setVisibleError(
			message === TAURI_RUNTIME_UNAVAILABLE
				? TAURI_RUNTIME_UNAVAILABLE
				: undefined,
		);
	}, []);

	const showError = useCallback((error: unknown) => {
		const message = error instanceof Error ? error.message : String(error);
		setStatus(message);
		setVisibleError(message);
	}, []);

	const {
		preferences,
		launchAtLogin,
		launchAtLoginLoading,
		updateLaunchAtLogin,
		updatePreferences,
	} = useCompanionSettings({ onError: showError, onStatus: showStatus });
	const activeTheme = resolvedCompanionTheme(preferences, systemThemeMode);

	const applyState = useCallback(
		(next: GlobalState) => {
			setState(next);
			showStatus("Updated");
		},
		[showStatus],
	);

	const refresh = useCallback(async () => {
		if (!tauriRuntimeAvailable) {
			showStatus(TAURI_RUNTIME_UNAVAILABLE);
			return;
		}
		try {
			applyState(await refreshWithActivity());
		} catch (error) {
			showError(error);
		}
	}, [
		applyState,
		refreshWithActivity,
		showError,
		showStatus,
		tauriRuntimeAvailable,
	]);

	const handleQuit = useCallback(() => {
		if (!tauriRuntimeAvailable) {
			showStatus(TAURI_RUNTIME_UNAVAILABLE);
			return;
		}
		void quitCompanion().catch(showError);
	}, [showError, showStatus, tauriRuntimeAvailable]);

	const handleTaskAction = useCallback(
		async (root: string, task: Task, kind: TaskActionKind) => {
			if (!tauriRuntimeAvailable) {
				showStatus(TAURI_RUNTIME_UNAVAILABLE);
				return;
			}
			const command = commandForTaskAction(task, kind);
			try {
				await runAction(command, root);
				applyState(await refreshWithActivity());
				showStatus("Action complete");
			} catch (error) {
				showError(error);
			}
		},
		[
			applyState,
			refreshWithActivity,
			showError,
			showStatus,
			tauriRuntimeAvailable,
		],
	);

	useEffect(() => {
		if (!tauriRuntimeAvailable) {
			return;
		}
		let stop: (() => void) | undefined;
		let cancelled = false;
		void startWorkspaceMonitor({
			refresh: refreshWithActivity,
			onState: applyState,
			onError: showError,
			watchRoots,
			onRootChanged,
			heartbeatMs: 5 * 60 * 1000,
			setTimer: (callback, milliseconds) =>
				window.setInterval(callback, milliseconds),
			clearTimer: (handle) => {
				window.clearInterval(handle);
			},
		})
			.then((monitor) => {
				if (cancelled) {
					monitor.stop();
				} else {
					stop = monitor.stop;
				}
			})
			.catch(showError);
		return () => {
			cancelled = true;
			stop?.();
		};
	}, [applyState, refreshWithActivity, showError, tauriRuntimeAvailable]);

	return (
		<main data-font={preferences.font} data-theme={activeTheme}>
			<header>
				<AppSummary summary={model.summary} />
				<AppToolbar
					onRefresh={() => void refresh()}
					onQuit={handleQuit}
					status={status}
				/>
			</header>
			<StatusAlert message={visibleError} />
			{currentView === "main" ? (
				<section className="view-panel" aria-label="Main View">
					{model.groups.length === 0 ? (
						<p className="empty">No workbranch tasks registered.</p>
					) : null}
					{model.groups.map((group) => (
						<ProjectGroup
							key={group.root}
							group={group}
							onAction={(root, task, kind) =>
								void handleTaskAction(root, task, kind)
							}
						/>
					))}
				</section>
			) : null}
			{currentView === "activity" ? (
				<section
					className="activity-view view-panel"
					aria-label="Activity report"
				>
					<h2>Activity report</h2>
					<p>Activity reporting will land in a future companion slice.</p>
				</section>
			) : null}
			{currentView === "settings" ? (
				<SettingsView
					preferences={preferences}
					systemThemeMode={systemThemeMode}
					launchAtLogin={launchAtLogin}
					launchAtLoginLoading={launchAtLoginLoading}
					onLaunchAtLoginChange={(enabled) => void updateLaunchAtLogin(enabled)}
					onPreferencesChange={(next) => void updatePreferences(next)}
				/>
			) : null}
			{model.errors.map((error) => (
				<p className="error" key={error.root}>
					{error.root}: {error.message}
				</p>
			))}
			<ViewNav currentView={currentView} onViewChange={setCurrentView} />
		</main>
	);
}
