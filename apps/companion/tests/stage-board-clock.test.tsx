import type { EffectCallback } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { BoardModel } from "../src/application/state";
import { StageBoard } from "../src/ui/StageBoard";

const effectCleanups = vi.hoisted((): Array<() => void> => []);

vi.mock("react", async (importOriginal) => {
	const react = await importOriginal<typeof import("react")>();
	return {
		...react,
		useEffect: (effect: EffectCallback) => {
			const cleanup = effect();
			if (cleanup !== undefined) effectCleanups.push(cleanup);
		},
	};
});

const EMPTY_BOARD: BoardModel = { cards: [], otherTasks: [] };

afterEach(() => {
	for (const cleanup of effectCleanups.splice(0)) cleanup();
	vi.useRealTimers();
	vi.unstubAllGlobals();
});

describe("StageBoard relative time clock", () => {
	it("schedules minute refreshes when no fixed time is provided", () => {
		vi.useFakeTimers();
		vi.stubGlobal("window", {
			setInterval: globalThis.setInterval,
			clearInterval: globalThis.clearInterval,
		});

		renderToStaticMarkup(
			<StageBoard board={EMPTY_BOARD} onOpenIde={() => undefined} />,
		);

		expect(vi.getTimerCount()).toBe(1);
	});
});
