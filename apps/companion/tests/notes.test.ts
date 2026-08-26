import { beforeEach, describe, expect, it, vi } from "vitest";
import {
	applyNoteUpdate,
	COMPANION_NOTES_STORE_FILE,
	type CompanionNoteStore,
	loadCompanionNoteStore,
	mergeLoadedRepoNotes,
	readRepoNotes,
	repoNoteKey,
	restoreFailedNoteUpdate,
	sanitizeRepoNotes,
	writeRepoNote,
} from "../src/application/notes";

const storeLoad = vi.hoisted(() => vi.fn());

vi.mock("@tauri-apps/plugin-store", () => ({ load: storeLoad }));

function fakeStore(entries: readonly (readonly [string, unknown])[] = []): {
	readonly calls: string[];
	readonly store: CompanionNoteStore;
} {
	const calls: string[] = [];
	return {
		calls,
		store: {
			entries: async () => entries,
			set: async (key, value) => {
				calls.push(`set:${key}:${String(value)}`);
			},
			delete: async (key) => {
				calls.push(`delete:${key}`);
				return true;
			},
			save: async () => {
				calls.push("save");
			},
		},
	};
}

beforeEach(() => {
	storeLoad.mockReset();
});

describe("repo notes", () => {
	it("builds a stable repository and branch key", () => {
		expect(repoNoteKey("backend", "feature/cpq-task-b")).toBe(
			"backend:feature/cpq-task-b",
		);
	});

	it("sanitizes note entries to trimmed non-empty strings", () => {
		expect(
			sanitizeRepoNotes([
				["a:b", "note"],
				["c:d", 7],
				["e:f", "  "],
				["g:h", "  keep me  "],
			]),
		).toEqual({ "a:b": "note", "g:h": "keep me" });
	});

	it("applies trimmed updates and removes blank notes immutably", () => {
		const original = { "a:b": "old" };

		expect(applyNoteUpdate(original, "a:b", "")).toEqual({});
		expect(applyNoteUpdate(original, "a:b", " new ")).toEqual({
			"a:b": "new",
		});
		expect(original).toEqual({ "a:b": "old" });
	});

	it("merges a delayed load without overwriting optimistic edits", () => {
		expect(
			mergeLoadedRepoNotes(
				{ "a:b": "stored", "c:d": "stored other", "e:f": "stored delete" },
				{ "a:b": "optimistic", "c:d": "new local" },
				new Set(["a:b", "c:d", "e:f"]),
			),
		).toEqual({
			"a:b": "optimistic",
			"c:d": "new local",
		});
	});

	it("rolls back only the failed key and preserves newer edits", () => {
		expect(
			restoreFailedNoteUpdate(
				{ "a:b": "attempted", "c:d": "newer" },
				{ "a:b": "old", "c:d": "before" },
				{ "a:b": "attempted", "c:d": "before" },
				"a:b",
			),
		).toEqual({ "a:b": "old", "c:d": "newer" });
		expect(
			restoreFailedNoteUpdate(
				{ "a:b": "newest", "c:d": "newer" },
				{ "a:b": "old", "c:d": "before" },
				{ "a:b": "attempted", "c:d": "before" },
				"a:b",
			),
		).toEqual({ "a:b": "newest", "c:d": "newer" });
	});

	it("loads the dedicated note store without autosave", async () => {
		const { store } = fakeStore();
		storeLoad.mockResolvedValue(store);

		await expect(loadCompanionNoteStore()).resolves.toBe(store);
		expect(storeLoad).toHaveBeenCalledWith(COMPANION_NOTES_STORE_FILE, {
			autoSave: false,
			defaults: {},
		});
	});

	it("reads and sanitizes stored notes", async () => {
		const { store } = fakeStore([
			["backend:main", " release note "],
			["frontend:main", false],
		]);

		await expect(readRepoNotes(store)).resolves.toEqual({
			"backend:main": "release note",
		});
	});

	it("sets non-empty notes and saves once", async () => {
		const { calls, store } = fakeStore();

		await writeRepoNote(store, "backend:main", " ship it ");

		expect(calls).toEqual(["set:backend:main:ship it", "save"]);
	});

	it("deletes blank notes and saves once", async () => {
		const { calls, store } = fakeStore();

		await writeRepoNote(store, "backend:main", "  ");

		expect(calls).toEqual(["delete:backend:main", "save"]);
	});
});
