import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { Children, isValidElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { AgentTabs, type CompanionView } from "../src/ui/AgentTabs";

type ButtonProps = {
	readonly "aria-label"?: string;
	readonly onClick?: () => void;
};

type TraversableProps = {
	readonly children?: ReactNode;
};

function collectButtons(node: ReactNode): readonly ButtonProps[] {
	const buttons: ButtonProps[] = [];
	const visit = (child: ReactNode): void => {
		if (!isValidElement<ButtonProps & TraversableProps>(child)) {
			return;
		}
		if (child.type === "button") {
			buttons.push(child.props);
		}
		Children.forEach(child.props.children, visit);
	};
	visit(node);
	return buttons;
}

function readCssContract(path: string): string {
	const css = readFileSync(path, "utf8");
	const importedCss = Array.from(css.matchAll(/@import "(.+)";/g))
		.map((match) => readCssContract(join(dirname(path), match[1] ?? "")))
		.join("\n");
	return `${css}\n${importedCss}`;
}

describe("AgentTabs", () => {
	it("renders a terminal view menu with the current view marked", () => {
		// Given the settings view is active
		// When the view navigation is rendered
		const html = renderToStaticMarkup(
			<AgentTabs currentView="settings" onViewChange={() => undefined} />,
		);

		// Then all view destinations are visible and the active one is exposed
		expect(html).toContain('aria-label="Companion views"');
		expect(html).toContain('aria-current="page"');
		expect(html).toContain("Main");
		expect(html).toContain("Activity");
		expect(html).toContain("Settings");
		expect(html).not.toContain("<svg");
	});

	it("renders a floating bottom tab row as three equal-width controls", () => {
		// Given the companion stylesheet for the bottom view navigation
		// When the nav button layout contract is inspected
		const css = readCssContract("src/style.css");

		// Then each menu item keeps the icon before the text with visible spacing
		expect(css).toMatch(
			/\.agent-tabs\s*\{[^}]*grid-template-columns:\s*repeat\(3,\s*minmax\(0,\s*1fr\)\)/s,
		);
		expect(css).toMatch(/\.agent-tabs\s*\{[^}]*position:\s*fixed/s);
		expect(css).toMatch(
			/main\s*\{[^}]*--floating-tabs-radius:\s*999px[^}]*--floating-tabs-shadow:/s,
		);
		expect(css).toMatch(
			/\.agent-tabs\s*\{[^}]*bottom:\s*calc\(var\(--floating-tabs-bottom\)/s,
		);
		expect(css).toMatch(
			/\.agent-tabs\s*\{[^}]*border-radius:\s*var\(--floating-tabs-radius\)/s,
		);
		expect(css).toMatch(
			/\.agent-tabs\s*\{[^}]*box-shadow:\s*var\(--floating-tabs-shadow\)/s,
		);
		expect(css).toMatch(/main\s*\{[^}]*padding-bottom:\s*[^;]+/s);
		expect(css).toMatch(
			/\.agent-tab\s*\{[^}]*font-size:\s*var\(--floating-tabs-font-size\)[^}]*min-height:\s*var\(--floating-tabs-height\)[^}]*min-width:\s*0/s,
		);
	});

	it("delegates clicks as view changes", () => {
		// Given a rendered view nav with an event sink
		const calls: CompanionView[] = [];
		const element = AgentTabs({
			currentView: "main",
			onViewChange: (view) => calls.push(view),
		});

		// When the Activity and Settings buttons are clicked
		const buttons = collectButtons(element);
		buttons[1]?.onClick?.();
		buttons[2]?.onClick?.();

		// Then the parent shell receives route-level view changes
		expect(calls).toEqual(["activity", "settings"]);
	});
});
