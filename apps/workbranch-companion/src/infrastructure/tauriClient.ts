import { invoke } from "@tauri-apps/api/core";
import type { GlobalState } from "../domain/model";
import { mapGlobalDocumentToState } from "./acl";
import { parseGlobalDocument } from "./parseContract";

export type CompanionCommand =
	| { readonly kind: "memo"; readonly task: string; readonly text: string }
	| { readonly kind: "memoClear"; readonly task: string }
	| { readonly kind: "notiClear"; readonly task: string }
	| { readonly kind: "finder"; readonly task: string }
	| { readonly kind: "ide"; readonly task: string }
	| { readonly kind: "terminal"; readonly task: string }
	| { readonly kind: "copyPath"; readonly path: string };

export async function refreshStatus(): Promise<GlobalState> {
	const raw = await invoke<string>("workbranch_list_global");
	return mapGlobalDocumentToState(parseGlobalDocument(raw));
}

export async function runAction(
	command: CompanionCommand,
	cwd: string,
): Promise<void> {
	await invoke("workbranch_run", { action: command, cwd });
}
