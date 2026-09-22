import { isTauri } from "@tauri-apps/api/core";
import { useCallback, useEffect, useRef, useState } from "react";
import {
	type CompanionLimitStore,
	type LimitAccounts,
	loadCompanionLimitStore,
	mergeLoadedLimitAccounts,
	readLimitAccounts,
	shouldRestoreFailedAccountsUpdate,
	writeLimitAccounts,
} from "./limits";
import { enqueuePreferenceSave } from "./preferences";

export type LimitAccountsState = {
	readonly accounts: LimitAccounts;
	readonly saveAccounts: (next: LimitAccounts) => Promise<void>;
};

type LimitAccountsOptions = {
	readonly onError: (error: unknown) => void;
	readonly onStatus: (status: string) => void;
};

export function useLimitAccounts({
	onError,
	onStatus,
}: LimitAccountsOptions): LimitAccountsState {
	const [accounts, setAccounts] = useState<LimitAccounts>([]);
	const accountsRef = useRef<LimitAccounts>([]);
	// The list last confirmed on disk; a failed save falls back to it rather
	// than to an earlier optimistic update that may never have persisted.
	const persistedRef = useRef<LimitAccounts>([]);
	const saveQueue = useRef<Promise<void>>(Promise.resolve());
	const storePromiseRef = useRef<Promise<CompanionLimitStore>>();
	const tauriRuntimeAvailable = isTauri();

	const enqueueWrite = useCallback((next: LimitAccounts): Promise<void> => {
		const save = enqueuePreferenceSave(saveQueue.current, async () => {
			const pendingStore = storePromiseRef.current ?? loadCompanionLimitStore();
			storePromiseRef.current = pendingStore;
			await writeLimitAccounts(await pendingStore, next);
			persistedRef.current = next;
		});
		saveQueue.current = save;
		return save;
	}, []);

	useEffect(() => {
		if (!tauriRuntimeAvailable) return;
		let cancelled = false;
		const baseline = accountsRef.current;
		async function loadAccounts(): Promise<void> {
			try {
				const storePromise = loadCompanionLimitStore();
				storePromiseRef.current = storePromise;
				const loaded = await readLimitAccounts(await storePromise);
				if (cancelled) return;
				if (accountsRef.current === baseline) {
					accountsRef.current = loaded;
					persistedRef.current = loaded;
					setAccounts(loaded);
					return;
				}
				// A local edit landed before the store answered: keep both and
				// write the merged list back so the edit does not drop stored rows.
				const merged = mergeLoadedLimitAccounts(loaded, accountsRef.current);
				accountsRef.current = merged;
				setAccounts(merged);
				await enqueueWrite(merged);
			} catch (error) {
				if (!cancelled) onError(error);
			}
		}
		void loadAccounts();
		return () => {
			cancelled = true;
		};
	}, [enqueueWrite, onError, tauriRuntimeAvailable]);

	const saveAccounts = useCallback(
		async (next: LimitAccounts) => {
			if (!tauriRuntimeAvailable) {
				onStatus("Tauri runtime unavailable");
				return;
			}
			accountsRef.current = next;
			setAccounts(next);
			try {
				await enqueueWrite(next);
				onStatus("Weekly limits updated");
			} catch (error) {
				const persisted = persistedRef.current;
				setAccounts((current) => {
					if (!shouldRestoreFailedAccountsUpdate(current, next)) {
						return current;
					}
					accountsRef.current = persisted;
					return persisted;
				});
				onError(error);
			}
		},
		[enqueueWrite, onError, onStatus, tauriRuntimeAvailable],
	);

	return { accounts, saveAccounts };
}
