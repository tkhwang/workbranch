import { isTauri } from "@tauri-apps/api/core";
import { useCallback, useEffect, useRef, useState } from "react";
import {
	type CompanionLimitStore,
	type LimitAccounts,
	loadCompanionLimitStore,
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
	const saveQueue = useRef<Promise<void>>(Promise.resolve());
	const storePromiseRef = useRef<Promise<CompanionLimitStore>>();
	const tauriRuntimeAvailable = isTauri();

	useEffect(() => {
		if (!tauriRuntimeAvailable) return;
		let cancelled = false;
		async function loadAccounts(): Promise<void> {
			try {
				const storePromise = loadCompanionLimitStore();
				storePromiseRef.current = storePromise;
				const loaded = await readLimitAccounts(await storePromise);
				if (cancelled) return;
				accountsRef.current = loaded;
				setAccounts(loaded);
			} catch (error) {
				if (!cancelled) onError(error);
			}
		}
		void loadAccounts();
		return () => {
			cancelled = true;
		};
	}, [onError, tauriRuntimeAvailable]);

	const saveAccounts = useCallback(
		async (next: LimitAccounts) => {
			if (!tauriRuntimeAvailable) {
				onStatus("Tauri runtime unavailable");
				return;
			}
			const previous = accountsRef.current;
			accountsRef.current = next;
			setAccounts(next);
			const save = enqueuePreferenceSave(saveQueue.current, async () => {
				const pendingStore =
					storePromiseRef.current ?? loadCompanionLimitStore();
				storePromiseRef.current = pendingStore;
				await writeLimitAccounts(await pendingStore, next);
			});
			saveQueue.current = save;
			try {
				await save;
				onStatus("Weekly limits updated");
			} catch (error) {
				setAccounts((current) => {
					if (!shouldRestoreFailedAccountsUpdate(current, next)) {
						return current;
					}
					accountsRef.current = previous;
					return previous;
				});
				onError(error);
			}
		},
		[onError, onStatus, tauriRuntimeAvailable],
	);

	return { accounts, saveAccounts };
}
