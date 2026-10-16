import { isTauri } from "@tauri-apps/api/core";
import { useCallback, useEffect, useRef, useState } from "react";
import { needsOnboarding, type SetupAction } from "./application/connections";
import {
	buildMainViewModel,
	buildMenuModel,
	type MenuModel,
} from "./application/state";
import { updateTargets } from "./application/updates";
import { useClaudeLimitRelay } from "./application/useClaudeLimitRelay";
import { useCompanionSettings } from "./application/useCompanionSettings";
import { useConnections } from "./application/useConnections";
import { useRepoNotes } from "./application/useRepoNotes";
import { useRuntimeSessions } from "./application/useRuntimeSessions";
import { useUpdates } from "./application/useUpdates";
import { useUsage } from "./application/useUsage";
import type { GlobalState, Task } from "./domain/model";
import {
	type CompanionCommand,
	companionErrorMessage,
	isCliCompatibilityError,
	type MigrationReport,
	migrateRuntime,
	onRootChanged,
	onWindowFocused,
	previewScreensaver,
	quitCompanion,
	refreshRoot,
	refreshStatus,
	runAction,
	watchRoots,
} from "./infrastructure/tauriClient";
import { startWorkspaceMonitor } from "./infrastructure/workspaceMonitor";
import { AgentHeader } from "./ui/AgentHeader";
import { AgentTabs, type CompanionView } from "./ui/AgentTabs";
import { ConnectionsPanel } from "./ui/ConnectionsPanel";
import { ProgressButton } from "./ui/ProgressButton";
import type { SettingsCategory } from "./ui/SettingsNav";
import { SettingsView } from "./ui/SettingsView";
import { StageBoard } from "./ui/StageBoard";
import { StatusAlert } from "./ui/StatusAlert";
import { StatusSettings } from "./ui/StatusSettings";
import type { TaskActionKind } from "./ui/TaskRow";
import { UsageSummary } from "./ui/UsageSummary";
import { UsageView } from "./ui/UsageView";

const EMPTY_STATE: GlobalState = { projects: [], errors: [] };
const TAURI_RUNTIME_UNAVAILABLE = "Tauri runtime unavailable";

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
	const stateRef = useRef<GlobalState>(EMPTY_STATE);
	const [status, setStatus] = useState("Ready");
	const [visibleError, setVisibleError] = useState<string>();
	const [setupError, setSetupError] = useState(false);
	const [currentView, setCurrentView] = useState<CompanionView>("main");
	const [settingsCategory, setSettingsCategory] =
		useState<SettingsCategory>("general");
	const [selectedStageTask, setSelectedStageTask] = useState<
		string | undefined
	>(undefined);
	const model: MenuModel = buildMenuModel(state);
	const [cliCompatible, setCliCompatible] = useState(false);
	const [migration, setMigration] = useState<MigrationReport>();
	const [migrating, setMigrating] = useState(false);
	const migrationInventoryRef = useRef<string>();
	const workspaceIdentity = JSON.stringify(
		state.projects
			.map((project) => [
				project.root,
				...project.tasks.map((task) => task.path).sort(),
			])
			.sort(),
	);
	const tauriRuntimeAvailable = isTauri();
	const runtime = useRuntimeSessions(tauriRuntimeAvailable && cliCompatible);
	const sessions = runtime.sessions;
	const runtimeNeedsCliUpdate =
		runtime.error !== undefined && isCliCompatibilityError(runtime.error);
	const runtimeError =
		runtime.error === undefined || runtimeNeedsCliUpdate
			? undefined
			: companionErrorMessage(runtime.error);
	const main = buildMainViewModel(state, sessions);
	const connections = useConnections(tauriRuntimeAvailable);
	const [onboardingDismissed, setOnboardingDismissed] = useState(false);
	const [setupStartedOnMain, setSetupStartedOnMain] = useState(false);
	const usage = useUsage(tauriRuntimeAvailable);

	const showStatus = useCallback((message: string) => {
		setStatus(message);
		setVisibleError(
			message === TAURI_RUNTIME_UNAVAILABLE
				? TAURI_RUNTIME_UNAVAILABLE
				: undefined,
		);
	}, []);

	const showError = useCallback((error: unknown) => {
		const message = companionErrorMessage(error);
		setSetupError(
			isCliCompatibilityError(error) ||
				/workbranch binary not found|runtime collector/i.test(String(error)),
		);
		if (isCliCompatibilityError(error)) setCliCompatible(false);
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
	const claudeLimitRelay = useClaudeLimitRelay(currentView === "settings", {
		onError: showError,
		onStatus: showStatus,
	});
	const { notes, saveNote } = useRepoNotes({
		onError: showError,
		onStatus: showStatus,
	});
	const activeTheme = preferences.theme;

	const applyState = useCallback(
		(next: GlobalState) => {
			setCliCompatible(true);
			stateRef.current = next;
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
			void usage.refresh();
			applyState(await refreshStatus());
			setMigration(await migrateRuntime(false));
		} catch (error) {
			showError(error);
		}
	}, [applyState, usage.refresh, showError, showStatus, tauriRuntimeAvailable]);

	// Opening the window replaces the removed manual refresh: it picks up
	// newly registered projects and retries after errors.
	const refreshingOnShow = useRef(false);
	useEffect(() => {
		if (!tauriRuntimeAvailable) return;
		let stop: (() => void) | undefined;
		let cancelled = false;
		void onWindowFocused(() => {
			if (refreshingOnShow.current) return;
			refreshingOnShow.current = true;
			void refresh().finally(() => {
				refreshingOnShow.current = false;
			});
		}).then((unlisten) => {
			if (cancelled) unlisten();
			else stop = unlisten;
		});
		return () => {
			cancelled = true;
			stop?.();
		};
	}, [refresh, tauriRuntimeAvailable]);

	const updates = useUpdates(tauriRuntimeAvailable, () => {
		void refresh();
		void connections.refresh();
	});
	const updateAvailable = updateTargets(updates.state.status).length > 0;
	// The header control opens the update status on Settings › General.
	const handleCheckUpdates = useCallback(() => {
		if (!tauriRuntimeAvailable) {
			showStatus(TAURI_RUNTIME_UNAVAILABLE);
			return;
		}
		setCurrentView("settings");
		setSettingsCategory("general");
		void updates.check();
	}, [showStatus, tauriRuntimeAvailable, updates.check]);

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
				applyState(await refreshStatus());
				showStatus("Action complete");
			} catch (error) {
				showError(error);
			}
		},
		[applyState, showError, showStatus, tauriRuntimeAvailable],
	);

	useEffect(() => {
		if (!tauriRuntimeAvailable) {
			return;
		}
		let stop: (() => void) | undefined;
		let cancelled = false;
		void startWorkspaceMonitor({
			refresh: refreshStatus,
			refreshRoot,
			getState: () => stateRef.current,
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
	}, [applyState, showError, tauriRuntimeAvailable]);

	// An incompatible CLI is a setup problem, shown like any other one; it
	// also turns cliCompatible off, which pauses the runtime subscription.
	useEffect(() => {
		if (runtimeNeedsCliUpdate) showError(runtime.error);
	}, [runtimeNeedsCliUpdate, runtime.error, showError]);

	// Discovery is keyed by workspace identity, never by tool activity.
	useEffect(() => {
		if (!tauriRuntimeAvailable || !cliCompatible) return;
		if (migrationInventoryRef.current === workspaceIdentity) return;
		let cancelled = false;
		void refreshStatus()
			.then(() => migrateRuntime(false))
			.then((report) => {
				if (!cancelled) {
					setMigration(report);
					migrationInventoryRef.current = workspaceIdentity;
				}
			})
			.catch(showError);
		return () => {
			cancelled = true;
		};
	}, [tauriRuntimeAvailable, cliCompatible, showError, workspaceIdentity]);
	const handleMigration = async () => {
		setMigrating(true);
		try {
			const result = await migrateRuntime(true);
			if (result.errors.length > 0) {
				setMigration(result);
				return;
			}
			setMigration(await migrateRuntime(false));
			await refresh();
			showStatus(
				"Migration complete. Restart agent sessions to reload instructions.",
			);
		} catch (error) {
			showError(error);
		} finally {
			setMigrating(false);
		}
	};

	const handleSetupAction = (action: SetupAction, onMain: boolean) => {
		setSetupStartedOnMain(onMain);
		void connections.run(action).then((ok) => {
			if (ok) void refresh();
		});
	};
	const connectionPanel = (onboarding: boolean) => (
		<ConnectionsPanel
			theme={activeTheme}
			state={connections.state}
			sessions={sessions}
			onRefresh={() => void connections.refresh()}
			onAction={(action) => handleSetupAction(action, onboarding)}
			onboarding={onboarding}
			onDismiss={() => setOnboardingDismissed(true)}
		/>
	);
	const showOnboarding =
		tauriRuntimeAvailable &&
		!onboardingDismissed &&
		needsOnboarding(connections.state, sessions, setupStartedOnMain);

	return (
		<main
			data-font={preferences.font}
			data-font-size={preferences.fontSize}
			data-theme={activeTheme}
		>
			<AgentHeader
				theme={activeTheme}
				summary={model.summary}
				status={status}
				onCheckUpdates={handleCheckUpdates}
				updateAvailable={updateAvailable}
				onQuit={handleQuit}
			/>
			<StatusAlert
				message={
					setupError && connections.state.status?.cli.state !== "ready"
						? undefined
						: visibleError
				}
			/>
			{runtimeError ? <p className="error">{runtimeError}</p> : null}
			{migration && (migration.pending > 0 || migration.errors.length > 0) ? (
				<section className="runtime-migration" aria-label="Runtime migration">
					<strong>새 agent 관측 방식으로 전환</strong>
					<p>구 상태 파일과 작성 지침 {migration.pending}개를 정리합니다.</p>
					<details>
						<summary>변경 대상 확인</summary>
						<ul>
							{migration.actions.map((a) => (
								<li key={a.path}>
									{a.kind}: {a.path}
								</li>
							))}
						</ul>
					</details>
					{migration.errors.map((error) => (
						<p className="error" key={error}>
							{error}
						</p>
					))}
					<ProgressButton
						pending={migrating}
						pendingLabel="전환 중…"
						onClick={() => void handleMigration()}
					>
						전환 실행
					</ProgressButton>
				</section>
			) : null}
			{currentView === "main" ? (
				<section className="view-panel" aria-label="Main View">
					{usage.snapshot ? (
						<UsageSummary
							onOpenDetails={() => setCurrentView("usage")}
							snapshot={usage.snapshot}
						/>
					) : null}
					{showOnboarding ? connectionPanel(true) : null}
					<StageBoard
						activeCount={main.activeCount}
						baseRows={main.baseRows}
						groups={main.stageGroups}
						idleCount={main.idleCount}
						idleRows={main.idleRows}
						notes={notes}
						onAction={(root, task, kind) =>
							void handleTaskAction(root, task, kind)
						}
						onSaveNote={(key, text) => void saveNote(key, text)}
						onSelect={setSelectedStageTask}
						selectedKey={selectedStageTask}
					/>
					{model.summary.taskCount === 0 ? (
						<p className="empty">No workbranch tasks registered.</p>
					) : null}
					{model.summary.taskCount > 0 && main.activeCount === 0 ? (
						<p className="empty">No active agent sessions.</p>
					) : null}
				</section>
			) : null}
			{currentView === "usage" ? (
				<UsageView error={usage.error} snapshot={usage.snapshot} />
			) : null}
			{currentView === "settings" ? (
				<SettingsView
					attention={{
						general: updateAvailable,
						connections:
							connections.state.status !== null &&
							connections.state.status.cli.state !== "ready",
					}}
					category={settingsCategory}
					onCategoryChange={setSettingsCategory}
					status={
						<StatusSettings
							connections={connections.state}
							onApplyUpdates={() => void updates.apply()}
							onCheckUpdates={() => void updates.check()}
							onOpenConnections={() => setSettingsCategory("connections")}
							updates={updates.state}
						/>
					}
					claudeLimitRelay={{
						status: claudeLimitRelay.status,
						loading: claudeLimitRelay.loading,
						onChange: (enabled) => void claudeLimitRelay.update(enabled),
					}}
					connections={connectionPanel(false)}
					preferences={preferences}
					launchAtLogin={launchAtLogin}
					launchAtLoginLoading={launchAtLoginLoading}
					onLaunchAtLoginChange={(enabled) => void updateLaunchAtLogin(enabled)}
					onPreferencesChange={(next) => void updatePreferences(next)}
					onScreensaverPreview={() => {
						if (!tauriRuntimeAvailable) {
							showStatus(TAURI_RUNTIME_UNAVAILABLE);
							return;
						}
						void previewScreensaver().catch(showError);
					}}
				/>
			) : null}
			{model.errors.map((error) => (
				<p className="error" key={error.root}>
					{error.root}: {error.message}
				</p>
			))}
			<AgentTabs currentView={currentView} onViewChange={setCurrentView} />
		</main>
	);
}
