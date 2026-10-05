export type UpdateTarget = "cli" | "companion";
export type PackageVersion = {
	readonly installed: string | null;
	readonly latest: string | null;
	readonly outdated: boolean;
};
export type UpdateStatus = {
	readonly brewPath: string | null;
	readonly fetchError: string | null;
	readonly runningVersion: string;
	readonly selfUpdateSupported: boolean;
	readonly cli: PackageVersion;
	readonly companion: PackageVersion;
};
export type UpdateRunResult = {
	readonly exitCode: number;
	readonly output: string;
	readonly restartRequired: boolean;
};
export type UpdateState = {
	readonly status: UpdateStatus | null;
	readonly checking: boolean;
	readonly updating: boolean;
	readonly restarting: boolean;
	readonly error: string | null;
	readonly notice: string | null;
	readonly logs: string;
};
export const EMPTY_UPDATE_STATE: UpdateState = {
	status: null,
	checking: false,
	updating: false,
	restarting: false,
	error: null,
	notice: null,
	logs: "",
};
type Services = {
	readonly inspect: (fetch: boolean) => Promise<UpdateStatus>;
	readonly apply: (
		targets: readonly UpdateTarget[],
		id: string,
	) => Promise<UpdateRunResult>;
	readonly subscribe: (
		id: string,
		receive: (text: string) => void,
	) => Promise<() => void>;
	readonly relaunch: () => Promise<void>;
	readonly id: () => string;
	readonly onUpdated?: () => void;
};
const limited = (value: string) => value.slice(-16000);

export function updateTargets(status: UpdateStatus | null): UpdateTarget[] {
	if (!status) return [];
	const targets: UpdateTarget[] = [];
	if (status.cli.outdated) targets.push("cli");
	if (status.companion.outdated && status.selfUpdateSupported)
		targets.push("companion");
	return targets;
}

/** Installed through the cask but still running an older bundle. */
export function companionRestartPending(status: UpdateStatus): boolean {
	return (
		status.selfUpdateSupported &&
		!status.companion.outdated &&
		status.companion.installed !== null &&
		status.companion.installed !== status.runningVersion
	);
}

export function updateActionLabel(targets: readonly UpdateTarget[]): string {
	if (targets.includes("companion"))
		return targets.includes("cli")
			? "모두 업데이트 후 재시작"
			: "Companion 업데이트 후 재시작";
	return "CLI 업데이트";
}

export function createUpdateController(
	services: Services,
	onChange: (state: UpdateState) => void,
) {
	let state: UpdateState = EMPTY_UPDATE_STATE;
	let disposed = false;
	let generation = 0;
	let stopLog: (() => void) | undefined;
	const update = (patch: Partial<UpdateState>) => {
		state = { ...state, ...patch };
		if (!disposed) onChange(state);
	};
	const inspect = async (fetch: boolean, keepMessages: boolean) => {
		const request = ++generation;
		update(
			keepMessages
				? { checking: true }
				: { checking: true, error: null, notice: null },
		);
		try {
			const status = await services.inspect(fetch);
			if (request === generation && !disposed)
				update({ status, checking: false });
		} catch (error) {
			if (request === generation && !disposed)
				update({
					checking: false,
					error:
						(keepMessages ? state.error : null) ??
						`최신 버전을 확인하지 못했습니다. ${String(error)}`,
				});
		}
	};
	const check = async () => {
		if (state.checking || state.updating || state.restarting || disposed)
			return;
		await inspect(true, false);
	};
	const apply = async (): Promise<boolean> => {
		const targets = updateTargets(state.status);
		if (
			targets.length === 0 ||
			state.checking ||
			state.updating ||
			state.restarting ||
			disposed
		)
			return false;
		++generation;
		update({ updating: true, error: null, notice: null, logs: "" });
		const id = services.id();
		try {
			stopLog = await services.subscribe(id, (text) => {
				if (!disposed) update({ logs: limited(state.logs + text) });
			});
			if (disposed) return false;
			const result = await services.apply(targets, id);
			update({ logs: limited(result.output) });
			if (result.exitCode !== 0) {
				update({
					error:
						"업데이트를 완료하지 못했습니다. 상세 로그를 확인하고 다시 시도하세요.",
				});
				return false;
			}
			if (result.restartRequired) {
				update({
					restarting: true,
					notice: "새 버전으로 Companion을 다시 시작합니다…",
				});
				await services.relaunch();
				return true;
			}
			update({ notice: "CLI 업데이트를 완료했습니다." });
			services.onUpdated?.();
			return true;
		} catch (error) {
			update({
				restarting: false,
				error: "업데이트를 실행하지 못했습니다. 다시 시도할 수 있습니다.",
				logs: limited(`${state.logs}\n${String(error)}`),
			});
			return false;
		} finally {
			stopLog?.();
			stopLog = undefined;
			update({ updating: false });
			// Reread installed versions only; the check already fetched.
			if (!state.restarting && !disposed) await inspect(false, true);
		}
	};
	return {
		check,
		apply,
		dispose: () => {
			disposed = true;
			++generation;
			stopLog?.();
		},
	};
}
