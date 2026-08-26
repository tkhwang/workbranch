import { load } from "@tauri-apps/plugin-store";

export const COMPANION_NOTES_STORE_FILE = "companion-notes.json";

export type CompanionNoteStore = {
	readonly entries: () => Promise<readonly (readonly [string, unknown])[]>;
	readonly set: (key: string, value: unknown) => Promise<void>;
	readonly delete: (key: string) => Promise<boolean>;
	readonly save: () => Promise<void>;
};

export type RepoNotes = Readonly<Record<string, string>>;

export function repoNoteKey(repoName: string, branch: string): string {
	return `${repoName}:${branch}`;
}

export function sanitizeRepoNotes(
	entries: readonly (readonly [string, unknown])[],
): RepoNotes {
	const notes: Record<string, string> = {};
	for (const [key, value] of entries) {
		if (typeof value !== "string") continue;
		const text = value.trim();
		if (text === "") continue;
		notes[key] = text;
	}
	return notes;
}

export function applyNoteUpdate(
	notes: RepoNotes,
	key: string,
	text: string,
): RepoNotes {
	const value = text.trim();
	if (value !== "") return { ...notes, [key]: value };
	return Object.fromEntries(
		Object.entries(notes).filter(([candidate]) => candidate !== key),
	);
}

export function shouldRestoreFailedNoteUpdate(
	current: RepoNotes,
	attempted: RepoNotes,
	key: string,
): boolean {
	return current[key] === attempted[key];
}

export async function loadCompanionNoteStore(): Promise<CompanionNoteStore> {
	return load(COMPANION_NOTES_STORE_FILE, {
		autoSave: false,
		defaults: {},
	});
}

export async function readRepoNotes(
	store: CompanionNoteStore,
): Promise<RepoNotes> {
	return sanitizeRepoNotes(await store.entries());
}

export async function writeRepoNote(
	store: CompanionNoteStore,
	key: string,
	text: string,
): Promise<void> {
	const value = text.trim();
	if (value === "") await store.delete(key);
	else await store.set(key, value);
	await store.save();
}
