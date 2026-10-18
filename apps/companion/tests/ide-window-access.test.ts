import { describe, expect, it } from "vitest";
import { accessAnswers } from "../src/application/useIdeWindowAccess";

describe("accessAnswers", () => {
	it("applies a read that nothing overtook", () => {
		const applied: boolean[] = [];
		const answers = accessAnswers((granted) => applied.push(granted));

		answers.read()(true);

		expect(applied).toEqual([true]);
	});

	it("drops a read that started before a request answered", () => {
		const applied: boolean[] = [];
		const answers = accessAnswers((granted) => applied.push(granted));

		const staleRead = answers.read();
		answers.request(true);
		staleRead(false);

		expect(applied).toEqual([true]);
	});

	it("applies reads that start after the request", () => {
		const applied: boolean[] = [];
		const answers = accessAnswers((granted) => applied.push(granted));

		answers.request(false);
		answers.read()(true);

		expect(applied).toEqual([false, true]);
	});
});
