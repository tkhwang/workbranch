import { isTauri } from "@tauri-apps/api/core";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { ActivityCalendarView } from "./activity/ActivityCalendarView";
import { createActivityRefresh } from "./application/activity";
import type { SetupAction } from "./application/connections";
import {
	buildMainViewModel,
	buildMenuModel,
	type MenuModel,
} from "./application/state";
import { updateTargets } from "./application/updates";
import { useCompanionSettings } from "./application/useCompanionSettings";
import { useConnections } from "./application/useConnections";
import { useLimitAccounts } from "./application/useLimitAccounts";
import { useRepoNotes } from "./application/useRepoNotes";
import { useUpdates } from "./application/useUpdates";
import type { AgentSession, GlobalState, Task } from "./domain/model";
import {
	appendActivityEvents,
	type CompanionCommand,
	companionErrorMessage,
	isCliCompatibilityError,
	type MigrationReport,
	migrateRuntime,
	onRootChanged,
	onWindowFocused,
	quitCompanion,
	readActivityEvents,
	refreshRoot,
	refreshRuntime,
	refreshStatus,
	runAction,
	watchRoots,
} from "./infrastructure/tauriClient";
import { startWorkspaceMonitor } from "./infrastructure/workspaceMonitor";
import { AgentHeader } from "./ui/AgentHeader";
import { AgentTabs, type CompanionView } from "./ui/AgentTabs";
import { ConnectionsPanel } from "./ui/ConnectionsPanel";
import { SettingsView } from "./ui/SettingsView";
import { StageBoard } from "./ui/StageBoard";
import { StatusAlert } from "./ui/StatusAlert";
import type { TaskActionKind } from "./ui/TaskRow";
import { UpdatePanel } from "./ui/UpdatePanel";
import { WeeklyLimitGauge } from "./ui/WeeklyLimitGauge";

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

export function nextActivityReloadToken(current: number): number {
	return current + 1;
}

export function App() {
	const [state, setState] = useState<GlobalState>(EMPTY_STATE);
	const stateRef = useRef<GlobalState>(EMPTY_STATE);
	const [activityReloadToken, setActivityReloadToken] = useState(0);
	const [status, setStatus] = useState("Ready");
	const [visibleError, setVisibleError] = useState<string>();
	const [setupError, setSetupError] = useState(false);
	const [currentView, setCurrentView] = useState<CompanionView>("main");
	const [selectedStageTask, setSelectedStageTask] = useState<
		string | undefined
	>(undefined);
	const model: MenuModel = buildMenuModel(state);
	const [sessions, setSessions] = useState<readonly AgentSession[]>([]);
	const [runtimeError, setRuntimeError] = useState<string>();
	const [cliCompatible, setCliCompatible] = useState(false);
	const [migration, setMigration] = useState<MigrationReport>();
	const [migrating, setMigrating] = useState(false);
	const migrationInventoryRef = useRef<string>();
	const main = buildMainViewModel(state, sessions);
	const workspaceIdentity = JSON.stringify(
		state.projects
			.map((project) => [
				project.root,
				...project.tasks.map((task) => task.path).sort(),
			])
			.sort(),
	);
	const tauriRuntimeAvailable = isTauri();
	const connections = useConnections(tauriRuntimeAvailable);
	const [onboardingDismissed, setOnboardingDismissed] = useState(false);
	const refreshWithActivity = useMemo(
		() =>
			createActivityRefresh({
				refresh: refreshStatus,
				refreshRoot,
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
	const { notes, saveNote } = useRepoNotes({
		onError: showError,
		onStatus: showStatus,
	});
	const { accounts, saveAccounts } = useLimitAccounts({
		onError: showError,
		onStatus: showStatus,
	});
	const activeTheme = preferences.theme;

	const applyState = useCallback(
		(next: GlobalState) => {
			setCliCompatible(true);
			stateRef.current = next;
			setState(next);
			setActivityReloadToken(nextActivityReloadToken);
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
			applyState(await refreshWithActivity.all());
			setMigration(await migrateRuntime(false));
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
	const [updatePanelOpen, setUpdatePanelOpen] = useState(false);
	const handleCheckUpdates = useCallback(() => {
		if (!tauriRuntimeAvailable) {
			showStatus(TAURI_RUNTIME_UNAVAILABLE);
			return;
		}
		setUpdatePanelOpen(true);
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
				applyState(await refreshWithActivity.all());
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
			refresh: refreshWithActivity.all,
			refreshRoot: refreshWithActivity.root,
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
	}, [applyState, refreshWithActivity, showError, tauriRuntimeAvailable]);

	useEffect(() => {
		if (!tauriRuntimeAvailable || !cliCompatible) {
			setRuntimeError(undefined);
			return;
		}
		let cancelled = false;
		let timer: number | undefined;
		const poll = async () => {
			try {
				const next = await refreshRuntime();
				if (!cancelled) {
					setSessions(next);
					setRuntimeError(undefined);
				}
			} catch (error) {
				if (!cancelled) {
					if (isCliCompatibilityError(error)) {
						showError(error);
						setRuntimeError(undefined);
						return;
					}
					setRuntimeError(companionErrorMessage(error));
					setSessions((previous) =>
						previous.map((s) => ({ ...s, observation: "uncertain" })),
					);
				}
			}
			if (!cancelled) timer = window.setTimeout(() => void poll(), 1000);
		};
		void poll();
		// Discovery is keyed by workspace identity, never by tool activity.
		if (migrationInventoryRef.current !== workspaceIdentity) {
			void refreshStatus()
				.then(() => migrateRuntime(false))
				.then((report) => {
					if (!cancelled) {
						setMigration(report);
						migrationInventoryRef.current = workspaceIdentity;
					}
				})
				.catch(showError);
		}

		return () => {
			cancelled = true;
			if (timer !== undefined) window.clearTimeout(timer);
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

	const handleSetupAction = (action: SetupAction) => {
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
			onAction={handleSetupAction}
			onboarding={onboarding}
			onDismiss={() => setOnboardingDismissed(true)}
		/>
	);
	const needsOnboarding =
		connections.state.busy !== null ||
		connections.state.notice !== null ||
		connections.state.error !== null ||
		connections.state.status === null ||
		connections.state.status.cli.state !== "ready" ||
		!connections.state.status.agents.some(
			(a) =>
				a.state === "configured" &&
				((a.lastObservedAt ?? 0) > 0 ||
					sessions.some((s) => s.provider === a.provider)),
		);

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
				updateAvailable={updateTargets(updates.state.status).length > 0}
				onQuit={handleQuit}
			/>
			{updatePanelOpen ? (
				<UpdatePanel
					theme={activeTheme}
					state={updates.state}
					onCheck={() => void updates.check()}
					onApply={() => void updates.apply()}
					onClose={() => setUpdatePanelOpen(false)}
				/>
			) : null}
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
					<button
						type="button"
						disabled={migrating}
						onClick={() => void handleMigration()}
					>
						{migrating ? "전환 중…" : "전환 실행"}
					</button>
				</section>
			) : null}
			{currentView === "main" ? (
				<section className="view-panel" aria-label="Main View">
					{tauriRuntimeAvailable && !onboardingDismissed && needsOnboarding
						? connectionPanel(true)
						: null}
					{accounts.length > 0 ? (
						<WeeklyLimitGauge accounts={accounts} />
					) : null}
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
			{currentView === "activity" ? (
				<section
					className="activity-view view-panel"
					aria-label="Activity calendar"
				>
					<ActivityCalendarView
						loadEvents={readActivityEvents}
						reloadToken={activityReloadToken}
						today={() => new Date()}
					/>
				</section>
			) : null}
			{currentView === "settings" ? (
				<SettingsView
					connections={connectionPanel(false)}
					accounts={accounts}
					preferences={preferences}
					launchAtLogin={launchAtLogin}
					launchAtLoginLoading={launchAtLoginLoading}
					onAccountsChange={(next) => void saveAccounts(next)}
					onLaunchAtLoginChange={(enabled) => void updateLaunchAtLogin(enabled)}
					onPreferencesChange={(next) => void updatePreferences(next)}
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
