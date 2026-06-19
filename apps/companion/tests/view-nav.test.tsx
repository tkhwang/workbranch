import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { Children, isValidElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { type CompanionView, ViewNav } from "../src/ui/ViewNav";

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

describe("ViewNav", () => {
	it("renders a mobile-style view menu with the current view marked", () => {
		// Given the settings view is active
		// When the view navigation is rendered
		const html = renderToStaticMarkup(
			<ViewNav currentView="settings" onViewChange={() => {}} />,
		);

		// Then all view destinations are visible and the active one is exposed
		expect(html).toContain('aria-label="Companion views"');
		expect(html).toContain('aria-label="Open Main View"');
		expect(html).toContain('aria-label="Open Activity report"');
		expect(html).toContain('aria-label="Open Settings"');
		expect(html).toContain('aria-current="page"');
		expect(html).toContain("Main");
		expect(html).toContain("Activity");
		expect(html).toContain("Setting");
	});

	it("renders bottom menu items as icon-leading text with spacing", () => {
		// Given the companion stylesheet for the bottom view navigation
		// When the nav button layout contract is inspected
		const css = readCssContract("src/style.css");

		// Then each menu item keeps the icon before the text with visible spacing
		expect(css).toMatch(
			/\.view-nav-button\s*\{[^}]*display:\s*inline-flex[^}]*gap:\s*7px/s,
		);
		expect(css).toMatch(/\.view-nav-button\s*\{[^}]*min-height:\s*40px/s);
	});

	it("delegates clicks as view changes", () => {
		// Given a rendered view nav with an event sink
		const calls: CompanionView[] = [];
		const element = ViewNav({
			currentView: "main",
			onViewChange: (view) => calls.push(view),
		});

		// When the Activity and Settings buttons are clicked
		const buttons = collectButtons(element);
		buttons
			.find((button) => button["aria-label"] === "Open Activity report")
			?.onClick?.();
		buttons
			.find((button) => button["aria-label"] === "Open Settings")
			?.onClick?.();

		// Then the parent shell receives route-level view changes
		expect(calls).toEqual(["activity", "settings"]);
	});
});
