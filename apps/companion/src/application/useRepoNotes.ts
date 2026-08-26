import { isTauri } from "@tauri-apps/api/core";
import { useCallback, useEffect, useRef, useState } from "react";
import {
	applyNoteUpdate,
	type CompanionNoteStore,
	loadCompanionNoteStore,
	mergeLoadedRepoNotes,
	type RepoNotes,
	readRepoNotes,
	restoreFailedNoteUpdate,
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
	const notesRef = useRef<RepoNotes>({});
	const editedKeysRef = useRef<Set<string>>(new Set());
	const storePromiseRef = useRef<Promise<CompanionNoteStore>>();
	const tauriRuntimeAvailable = isTauri();

	useEffect(() => {
		if (!tauriRuntimeAvailable) return;
		let cancelled = false;
		async function loadNotes(): Promise<void> {
			try {
				const storePromise = loadCompanionNoteStore();
				storePromiseRef.current = storePromise;
				const store = await storePromise;
				const loaded = await readRepoNotes(store);
				if (cancelled) return;
				setNoteStore(store);
				setNotes((current) => {
					const merged = mergeLoadedRepoNotes(
						loaded,
						current,
						editedKeysRef.current,
					);
					notesRef.current = merged;
					return merged;
				});
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
			const previous = notesRef.current;
			const attempted = applyNoteUpdate(previous, key, text);
			editedKeysRef.current.add(key);
			notesRef.current = attempted;
			setNotes(attempted);
			const save = enqueuePreferenceSave(saveQueue.current, async () => {
				const pendingStore =
					storePromiseRef.current ?? loadCompanionNoteStore();
				storePromiseRef.current = pendingStore;
				const store = noteStore ?? (await pendingStore);
				setNoteStore(store);
				await writeRepoNote(store, key, text);
			});
			saveQueue.current = save;
			try {
				await save;
				onStatus(attempted[key] === undefined ? "Note removed" : "Note saved");
			} catch (error) {
				setNotes((current) => {
					const restored = restoreFailedNoteUpdate(
						current,
						previous,
						attempted,
						key,
					);
					notesRef.current = restored;
					return restored;
				});
				onError(error);
			}
		},
		[noteStore, onError, onStatus, tauriRuntimeAvailable],
	);

	return { notes, saveNote };
}
