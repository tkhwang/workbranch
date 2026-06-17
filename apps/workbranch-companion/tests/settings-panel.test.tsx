import { Children, isValidElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import type {
	CompanionFont,
	CompanionPreferences,
	CompanionTheme,
} from "../src/application/preferences";
import { SettingsPanel } from "../src/ui/SettingsPanel";

type InputProps = {
	readonly id?: string;
	readonly checked?: boolean;
	readonly disabled?: boolean;
	readonly onChange?: (event: {
		readonly currentTarget: { readonly checked: boolean };
	}) => void;
};

type SelectProps = {
	readonly id?: string;
	readonly value?: string;
	readonly onChange?: (event: {
		readonly currentTarget: { readonly value: string };
	}) => void;
};

function collectByType<TProps>(
	node: ReactNode,
	typeName: "input" | "select",
): readonly TProps[] {
	const props: TProps[] = [];
	const visit = (child: ReactNode): void => {
		if (!isValidElement<TProps>(child)) {
			return;
		}
		if (child.type === typeName) {
			props.push(child.props);
		}
		Children.forEach(child.props.children, visit);
	};
	visit(node);
	return props;
}

const preferences: CompanionPreferences = {
	font: "system-mono",
	theme: "terminal-dark",
};

describe("SettingsPanel", () => {
	it("renders labeled fieldsets for startup, font, and theme controls", () => {
		// Given current companion preferences and launch-at-login status
		// When the settings panel is rendered
		const html = renderToStaticMarkup(
			<SettingsPanel
				preferences={preferences}
				launchAtLogin={false}
				launchAtLoginLoading={false}
				onLaunchAtLoginChange={() => {}}
				onPreferencesChange={() => {}}
			/>,
		);

		// Then semantic groups, labels, and fixed choices are visible
		expect(html).toContain("<fieldset");
		expect(html).toContain("<h2>Setting</h2>");
		expect(html).toContain("<legend>Startup</legend>");
		expect(html).toContain("<legend>Font</legend>");
		expect(html).toContain("<legend>Theme</legend>");
		expect(html).toContain('for="launch-at-login"');
		expect(html).toContain('for="companion-font"');
		expect(html).toContain('for="companion-theme"');
		expect(html).toContain("Launch at login");
		expect(html).toContain("System Mono");
		expect(html).toContain("JetBrains Mono");
		expect(html).toContain("Terminal Dark");
		expect(html).toContain("High Contrast");
	});

	it("delegates launch, font, and theme updates to app-shell callbacks", () => {
		// Given a rendered settings panel with callback spies
		const launchCalls: boolean[] = [];
		const preferenceCalls: CompanionPreferences[] = [];
		const element = SettingsPanel({
			preferences,
			launchAtLogin: false,
			launchAtLoginLoading: false,
			onLaunchAtLoginChange: (enabled) => {
				launchCalls.push(enabled);
			},
			onPreferencesChange: (next) => {
				preferenceCalls.push(next);
			},
			onClose: () => {},
		});

		// When controls change
		const launchToggle = collectByType<InputProps>(element, "input").find(
			(input) => input.id === "launch-at-login",
		);
		const selects = collectByType<SelectProps>(element, "select");
		const fontSelect = selects.find((select) => select.id === "companion-font");
		const themeSelect = selects.find(
			(select) => select.id === "companion-theme",
		);
		launchToggle?.onChange?.({ currentTarget: { checked: true } });
		fontSelect?.onChange?.({
			currentTarget: { value: "menlo" satisfies CompanionFont },
		});
		themeSelect?.onChange?.({
			currentTarget: { value: "green-mono" satisfies CompanionTheme },
		});

		// Then the app shell receives every change without the panel swallowing failures
		expect(launchCalls).toEqual([true]);
		expect(preferenceCalls).toEqual([
			{ font: "menlo", theme: "terminal-dark" },
			{ font: "system-mono", theme: "green-mono" },
		]);
	});
});
