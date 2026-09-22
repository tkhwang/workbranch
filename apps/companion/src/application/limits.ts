import { load } from "@tauri-apps/plugin-store";
import { addLocalDays, LIMIT_WINDOW_DAYS } from "../domain/limits";

export const COMPANION_LIMITS_STORE_FILE = "companion-limits.json";
export const LIMIT_ACCOUNTS_STORE_KEY = "accounts";
export const MAX_LIMIT_ACCOUNTS = 12;
export const LIMIT_LABEL_MAX_LENGTH = 40;

export type LimitAccount = {
	readonly id: string;
	readonly label: string;
	// Epoch seconds of the next reset as the user entered it; the domain
	// normalizes it onto the weekly cadence whenever it is read.
	readonly nextResetAt: number;
};

export type LimitAccounts = readonly LimitAccount[];

export type CompanionLimitStore = {
	readonly get: <T>(key: string) => Promise<T | undefined>;
	readonly set: (key: string, value: unknown) => Promise<void>;
	readonly save: () => Promise<void>;
};

export function isEpochSeconds(value: unknown): value is number {
	return typeof value === "number" && Number.isSafeInteger(value) && value > 0;
}

function sanitizeLabel(value: unknown): string {
	if (typeof value !== "string") return "";
	return value.trim().slice(0, LIMIT_LABEL_MAX_LENGTH);
}

export function sanitizeLimitAccounts(value: unknown): LimitAccounts {
	if (!Array.isArray(value)) return [];
	const accounts: LimitAccount[] = [];
	const seen = new Set<string>();
	for (const entry of value) {
		if (accounts.length >= MAX_LIMIT_ACCOUNTS) break;
		if (typeof entry !== "object" || entry === null) continue;
		const record = entry as Record<string, unknown>;
		const id = record["id"];
		const nextResetAt = record["nextResetAt"];
		if (typeof id !== "string" || id === "" || seen.has(id)) continue;
		if (!isEpochSeconds(nextResetAt)) continue;
		seen.add(id);
		accounts.push({ id, label: sanitizeLabel(record["label"]), nextResetAt });
	}
	return accounts;
}

export function newLimitAccount(
	existing: LimitAccounts,
	now: Date,
	createId: () => string,
): LimitAccount {
	const hourStart = new Date(now);
	hourStart.setMinutes(0, 0, 0);
	return {
		id: createId(),
		label: `Account ${existing.length + 1}`,
		nextResetAt: addLocalDays(
			Math.floor(hourStart.getTime() / 1000),
			LIMIT_WINDOW_DAYS,
		),
	};
}

export function limitAccountDisplayLabel(
	account: LimitAccount,
	index: number,
): string {
	return account.label === "" ? `Account ${index + 1}` : account.label;
}

export function shouldRestoreFailedAccountsUpdate(
	current: LimitAccounts,
	attempted: LimitAccounts,
): boolean {
	return current === attempted;
}

export async function loadCompanionLimitStore(): Promise<CompanionLimitStore> {
	return load(COMPANION_LIMITS_STORE_FILE, {
		autoSave: false,
		defaults: {},
	});
}

export async function readLimitAccounts(
	store: CompanionLimitStore,
): Promise<LimitAccounts> {
	return sanitizeLimitAccounts(
		await store.get<unknown>(LIMIT_ACCOUNTS_STORE_KEY),
	);
}

export async function writeLimitAccounts(
	store: CompanionLimitStore,
	accounts: LimitAccounts,
): Promise<void> {
	await store.set(LIMIT_ACCOUNTS_STORE_KEY, accounts);
	await store.save();
}
