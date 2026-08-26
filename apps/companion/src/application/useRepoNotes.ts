import { isTauri } from "@tauri-apps/api/core";
import { useCallback, useEffect, useRef, useState } from "react";
import {
	applyNoteUpdate,
	type CompanionNoteStore,
	loadCompanionNoteStore,
	type RepoNotes,
	readRepoNotes,
	shouldRestoreFailedNoteUpdate,
	writeRepoNote,
} from "./notes";
import { enqueuePreferenceSave } from "./preferences";

export type RepoNotesState = {
	readonly notes: RepoNotes;
	readonly saveNote: (key: string, text: string) => Promise<void>;
};

type RepoNotesOptions = {
	readonly onError: (error: unknown) => void;
	readonly onStatus: (status: string) => void;
};

export function useRepoNotes({
	onError,
	onStatus,
}: RepoNotesOptions): RepoNotesState {
	const [notes, setNotes] = useState<RepoNotes>({});
	const [noteStore, setNoteStore] = useState<CompanionNoteStore>();
	const saveQueue = useRef<Promise<void>>(Promise.resolve());
	const tauriRuntimeAvailable = isTauri();

	useEffect(() => {
		if (!tauriRuntimeAvailable) return;
		let cancelled = false;
		async function loadNotes(): Promise<void> {
			try {
				const store = await loadCompanionNoteStore();
				const loaded = await readRepoNotes(store);
				if (cancelled) return;
				setNoteStore(store);
				setNotes(loaded);
			} catch (error) {
				if (!cancelled) onError(error);
			}
		}
		void loadNotes();
		return () => {
			cancelled = true;
		};
	}, [onError, tauriRuntimeAvailable]);

	const saveNote = useCallback(
		async (key: string, text: string) => {
			if (!tauriRuntimeAvailable) {
				onStatus("Tauri runtime unavailable");
				return;
			}
			const previous = notes;
			const attempted = applyNoteUpdate(notes, key, text);
			setNotes(attempted);
			const save = enqueuePreferenceSave(saveQueue.current, async () => {
				const store = noteStore ?? (await loadCompanionNoteStore());
				setNoteStore(store);
				await writeRepoNote(store, key, text);
			});
			saveQueue.current = save;
			try {
				await save;
				onStatus(attempted[key] === undefined ? "Note removed" : "Note saved");
			} catch (error) {
				setNotes((current) =>
					shouldRestoreFailedNoteUpdate(current, attempted, key)
						? previous
						: current,
				);
				onError(error);
			}
		},
		[noteStore, notes, onError, onStatus, tauriRuntimeAvailable],
	);

	return { notes, saveNote };
}
