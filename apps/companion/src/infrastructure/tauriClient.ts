import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import {
	type CalendarEventInput,
	calendarEventFromUnknown,
} from "../activity/calendar";
import type { ActivityEvent } from "../application/activity";
import type { GlobalState, Project } from "../domain/model";
import { mapGlobalDocumentToState, mapListDocumentToProject } from "./acl";
import {
	parseGlobalDocument,
	parseListDocument,
	parseRuntimeDocument,
} from "./parseContract";

export type RunResult = {
	readonly exit_code: number;
	readonly stdout: string;
	readonly stderr: string;
};

export class CompanionActionError extends Error {
	readonly exitCode: number;
	readonly stdout: string;
	readonly stderr: string;

	constructor(result: RunResult) {
		super(
			result.stderr || `workbranch action failed with exit ${result.exit_code}`,
		);
		this.name = "CompanionActionError";
		this.exitCode = result.exit_code;
		this.stdout = result.stdout;
		this.stderr = result.stderr;
	}
}

export function ensureRunSucceeded(result: RunResult): void {
	if (result.exit_code !== 0) {
		throw new CompanionActionError(result);
	}
}

export type CompanionCommand =
	| { readonly kind: "finder"; readonly task: string }
	| { readonly kind: "ide"; readonly task: string }
	| { readonly kind: "terminal"; readonly task: string };

export async function refreshStatus(): Promise<GlobalState> {
	const raw = await invoke<string>("workbranch_list_global");
	return mapGlobalDocumentToState(parseGlobalDocument(raw));
}

export async function refreshRoot(root: string): Promise<Project> {
	const raw = await invoke<string>("workbranch_list", { root });
	return mapListDocumentToProject(parseListDocument(raw));
}

export async function appendActivityEvents(
	events: readonly ActivityEvent[],
): Promise<void> {
	if (events.length === 0) {
		return;
	}
	await invoke("append_activity_events", { events });
}

export async function quitCompanion(): Promise<void> {
	await invoke("quit_app");
}

export async function readActivityEvents(
	fromEpoch: number,
	toEpoch: number,
): Promise<readonly CalendarEventInput[]> {
	const raw = await invoke<readonly unknown[]>("read_activity_events", {
		fromEpoch,
		toEpoch,
	});
	return raw
		.map(calendarEventFromUnknown)
		.filter((event): event is CalendarEventInput => event !== undefined);
}

export async function runAction(
	command: CompanionCommand,
	cwd: string,
): Promise<void> {
	const result = await invoke<RunResult>("workbranch_run", {
		action: command,
		cwd,
	});
	ensureRunSucceeded(result);
}

export async function watchRoots(roots: readonly string[]): Promise<void> {
	await invoke("watch_roots", { roots });
}

export async function onRootChanged(
	callback: (root: string) => void,
): Promise<() => void> {
	return listen<string>("roots-changed", (event) => callback(event.payload));
}

export async function refreshRuntime(): Promise<
	readonly import("../domain/model").AgentSession[]
> {
	return parseRuntimeDocument(await invoke<string>("workbranch_runtime"));
}
export type MigrationReport = {
	readonly schemaVersion: 1;
	readonly pending: number;
	readonly applied: number;
	readonly actions: readonly { readonly path: string; readonly kind: string }[];
	readonly errors: readonly string[];
};
export async function migrateRuntime(apply = false): Promise<MigrationReport> {
	const result = await invoke<RunResult>("workbranch_migrate", { apply });
	if (!result.stdout) ensureRunSucceeded(result);
	const value: unknown = JSON.parse(result.stdout);
	if (
		typeof value !== "object" ||
		value === null ||
		!("schemaVersion" in value) ||
		value.schemaVersion !== 1 ||
		!("actions" in value) ||
		!Array.isArray(value.actions) ||
		!("errors" in value) ||
		!Array.isArray(value.errors) ||
		!("pending" in value) ||
		typeof value.pending !== "number"
	)
		throw new Error("Invalid migration report; update workbranch");
	return value as MigrationReport;
}

export function isCliCompatibilityError(error: unknown): boolean {
	const message = error instanceof Error ? error.message : String(error);
	return /incompatible schema version|unknown command:\s*(?:runtime|migrate)\b/i.test(
		message,
	);
}
export function companionErrorMessage(error: unknown): string {
	const message = error instanceof Error ? error.message : String(error);
	if (isCliCompatibilityError(error))
		return "현재 CLI가 새 Companion과 호환되지 않습니다. CLI와 runtime 수집기를 함께 업데이트한 뒤 새로고침하세요.";
	if (
		/workbranch-agent-runtime missing|runtime collector unavailable|Build the runtime collector/i.test(
			message,
		)
	)
		return "Runtime 수집기가 준비되지 않았습니다. workbranch와 수집기를 함께 설치하거나 개발용 수집기를 빌드한 뒤 새로고침하세요.";
	if (
		/incompatible snapshot|incompatible database schema|database is newer/i.test(
			message,
		)
	)
		return "Runtime 수집기의 버전이 맞지 않습니다. CLI·수집기·Companion을 함께 업데이트하세요.";
	const useful =
		message
			.split(/\r?\n/)
			.filter((line) => line.trim() !== "")
			.at(-1) ?? "요청을 처리하지 못했습니다.";
	return useful.length > 240 ? `${useful.slice(0, 240)}…` : useful;
}

export async function inspectSetup(): Promise<
	import("../application/connections").SetupStatus
> {
	return invoke("setup_status");
}
export async function runSetupAction(
	action: import("../application/connections").SetupAction,
	operationId: string,
): Promise<RunResult> {
	return invoke("setup_action", { action, operationId });
}
export async function onSetupProgress(
	operationId: string,
	receive: (text: string) => void,
): Promise<() => void> {
	return listen<{ operationId: string; text: string }>(
		"setup-progress",
		(event) => {
			if (event.payload.operationId === operationId)
				receive(event.payload.text);
		},
	);
}
