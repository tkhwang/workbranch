import type { WorkbranchChecklistItem } from "@workbranch/contract";
import type { Step } from "./model";

type MutableStep = {
	text: string;
	checked: boolean;
	depth: number;
	children: MutableStep[];
};

function freezeStep(step: MutableStep): Step {
	return {
		text: step.text,
		checked: step.checked,
		depth: step.depth,
		children: step.children.map(freezeStep),
	};
}

export function buildStepTree(
	items: readonly WorkbranchChecklistItem[],
): readonly Step[] {
	const roots: MutableStep[] = [];
	const stack: MutableStep[] = [];
	for (const item of items) {
		const node: MutableStep = {
			text: item.text,
			checked: item.checked,
			depth: item.depth,
			children: [],
		};
		while (stack.length > item.depth) {
			stack.pop();
		}
		const parent = item.depth > 0 ? stack[item.depth - 1] : undefined;
		if (parent) {
			parent.children.push(node);
		} else {
			roots.push(node);
		}
		stack[item.depth] = node;
	}
	return roots.map(freezeStep);
}
