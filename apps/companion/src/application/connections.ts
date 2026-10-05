export type Provider = "claude" | "codex" | "grok";
export type SetupAction =
	| { readonly kind: "installCli" | "updateCli" | "repairCli" }
	| {
			readonly kind: "connectAgent";
			readonly approvedSource?: string;
			readonly provider: Provider;
	  }
	| { readonly kind: "disconnectAgent"; readonly provider: Provider };
export type SetupStatus = {
	readonly brewPath: string | null;
	readonly formulaInstalled: boolean | null;
	readonly cli: {
		readonly state: "missing" | "incompatible" | "runtimeUnavailable" | "ready";
		readonly path: string | null;
		readonly version: string;
		readonly message: string;
	};
	readonly agents: readonly {
		readonly provider: Provider;
		readonly executablePath: string | null;
		readonly installSource?: string | null;
		readonly state:
			| "notInstalled"
			| "disconnected"
			| "disabled"
			| "trustRequired"
			| "configured"
			| "unknown";
		readonly lastObservedAt: number | null;
		readonly message: string;
	}[];
};
export type ConnectionState = {
	readonly status: SetupStatus | null;
	readonly loading: boolean;
	readonly busy: SetupAction | null;
	/** The action `error`/`notice` report on; null when a status check failed. */
	readonly lastAction: SetupAction | null;
	readonly error: string | null;
	readonly logs: string;
	readonly notice: string | null;
	readonly verificationAfter: Partial<Record<Provider, number>>;
};
export const EMPTY_CONNECTION_STATE: ConnectionState = {
	status: null,
	loading: true,
	busy: null,
	lastAction: null,
	error: null,
	logs: "",
	notice: null,
	verificationAfter: {},
};
type Result = {
	readonly exit_code: number;
	readonly stdout: string;
	readonly stderr: string;
};
type Services = {
	readonly inspect: () => Promise<SetupStatus>;
	readonly run: (action: SetupAction, id: string) => Promise<Result>;
	readonly subscribe: (
		id: string,
		receive: (text: string) => void,
	) => Promise<() => void>;
	readonly id: () => string;
	readonly now?: () => number;
};
const limited = (value: string) => value.slice(-16000);
export function createConnectionController(
	services: Services,
	onChange: (state: ConnectionState) => void,
) {
	let state: ConnectionState = EMPTY_CONNECTION_STATE;
	let disposed = false;
	let generation = 0;
	let stopLog: (() => void) | undefined;
	const now = services.now ?? (() => Math.floor(Date.now() / 1000));
	const update = (patch: Partial<ConnectionState>) => {
		state = { ...state, ...patch };
		if (!disposed) onChange(state);
	};
	const refresh = async () => {
		if (state.busy || disposed) return;
		const request = ++generation;
		update({ loading: true, error: null });
		try {
			const status = await services.inspect();
			if (request === generation && !disposed)
				update({
					status,
					loading: false,
					verificationAfter: Object.fromEntries(
						status.agents.map((a) => [
							a.provider,
							state.verificationAfter[a.provider] ?? now(),
						]),
					),
				});
		} catch {
			if (request === generation && !disposed)
				update({
					loading: false,
					lastAction: null,
					error: "설치 상태를 확인하지 못했습니다. 다시 확인을 눌러 주세요.",
				});
		}
	};
	const run = async (action: SetupAction): Promise<boolean> => {
		if (state.busy || disposed) return false;
		++generation;
		update({
			busy: action,
			lastAction: action,
			loading: false,
			error: null,
			notice: null,
			logs: "",
		});
		const id = services.id();
		try {
			stopLog = await services.subscribe(id, (text) => {
				if (!disposed) update({ logs: limited(state.logs + text) });
			});
			if (disposed) {
				stopLog();
				return false;
			}
			const result = await services.run(action, id);
			update({
				logs: limited(
					[result.stdout, result.stderr].filter(Boolean).join("\n"),
				),
			});
			const status = await services.inspect();
			update({ status });
			if (action.kind === "connectAgent")
				update({
					verificationAfter: {
						...state.verificationAfter,
						[action.provider]: now(),
					},
				});
			else if (action.kind.endsWith("Cli"))
				update({
					verificationAfter: Object.fromEntries(
						status.agents.map((a) => [a.provider, now()]),
					),
				});
			if (result.exit_code !== 0) {
				update({
					error:
						action.kind === "connectAgent" &&
						action.provider === "grok" &&
						/requires confirmation|re-run with --trust/i.test(
							result.stdout + result.stderr,
						)
							? "Grok plugin 설치에 신뢰 승인이 필요합니다. 연결 버튼에서 설치 대상을 확인하고 승인하세요."
							: "작업을 완료하지 못했습니다. 상세 로그를 확인하고 다시 시도하세요.",
				});
				return false;
			}
			if (
				(action.kind === "installCli" ||
					action.kind === "updateCli" ||
					action.kind === "repairCli") &&
				status.cli.state !== "ready"
			) {
				update({
					error:
						"설치는 끝났지만 호환성을 확인하지 못했습니다. 선택된 CLI 경로와 버전을 확인하세요.",
				});
				return false;
			}

			if (action.kind === "connectAgent" || action.kind === "disconnectAgent") {
				const agent = status.agents.find((a) => a.provider === action.provider);
				const confirmed =
					action.kind === "connectAgent"
						? agent?.state === "configured" || agent?.state === "trustRequired"
						: agent?.state === "disconnected";
				if (!confirmed) {
					update({
						error:
							"명령은 끝났지만 연결 설정을 확인하지 못했습니다. Agent의 plugin 상태와 상세 로그를 확인하세요.",
					});
					return false;
				}
			}
			update({
				notice:
					action.kind === "connectAgent"
						? "설정 후 agent를 다시 시작하고 hook 신뢰 상태를 확인하세요. 첫 이벤트 수신으로 연결을 검증합니다."
						: action.kind === "disconnectAgent"
							? "연결 해제 요청을 처리했습니다. Agent를 다시 시작하세요."
							: "CLI와 수집기 준비가 완료됐습니다.",
			});
			return true;
		} catch (error) {
			update({
				error: "설치 또는 연결 작업에 실패했습니다. 다시 시도할 수 있습니다.",
				logs: limited(state.logs + "\n" + String(error)),
			});
			return false;
		} finally {
			stopLog?.();
			stopLog = undefined;
			update({ busy: null });
		}
	};
	return {
		refresh,
		run,
		dispose: () => {
			disposed = true;
			++generation;
			stopLog?.();
		},
	};
}

export function cliSetupAction(
	status: SetupStatus,
): "installCli" | "updateCli" | "repairCli" {
	if (status.formulaInstalled !== true) return "installCli";
	return status.cli.state === "runtimeUnavailable" ? "repairCli" : "updateCli";
}
/** The CLI step or agent row an action belongs to. */
export function setupTarget(action: SetupAction): "cli" | Provider {
	return "provider" in action ? action.provider : "cli";
}
/** Same button: kind and target match; an approved Grok source does not matter. */
export function sameSetupAction(a: SetupAction, b: SetupAction): boolean {
	return a.kind === b.kind && setupTarget(a) === setupTarget(b);
}
export function receiptState(
	observedAt: number,
	after: number | undefined,
): "waiting" | "historical" | "verified" {
	if (observedAt <= 0) return "waiting";
	return after !== undefined && observedAt > after ? "verified" : "historical";
}
