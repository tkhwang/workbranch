import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import {
	type CalendarEventInput,
	calendarEventFromUnknown,
} from "../activity/calendar";
import type { ActivityEvent } from "../application/activity";
import type { GlobalState, Project } from "../domain/model";
import { mapGlobalDocumentToState, mapListDocumentToProject } from "./acl";
import { parseGlobalDocument, parseListDocument } from "./parseContract";

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
