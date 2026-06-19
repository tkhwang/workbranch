import { Children, isValidElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import type {
	CompanionFont,
	CompanionPreferences,
	CompanionResolvedThemeMode,
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

type ButtonProps = {
	readonly "aria-label"?: string;
	readonly "aria-pressed"?: boolean;
	readonly onClick?: () => void;
};

type TraversableProps = {
	readonly children?: ReactNode;
};

function collectByType<TProps>(
	node: ReactNode,
	typeName: "button" | "input" | "select",
): readonly TProps[] {
	const props: TProps[] = [];
	const visit = (child: ReactNode): void => {
		if (!isValidElement<TProps & TraversableProps>(child)) {
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
	themeFamily: "dracula",
	themeMode: "system",
};

function renderSettingsPanel({
	currentPreferences = preferences,
	systemThemeMode = "dark",
}: {
	readonly currentPreferences?: CompanionPreferences;
	readonly systemThemeMode?: CompanionResolvedThemeMode;
} = {}): string {
	return renderToStaticMarkup(
		<SettingsPanel
			preferences={currentPreferences}
			systemThemeMode={systemThemeMode}
			launchAtLogin={false}
			launchAtLoginLoading={false}
			onLaunchAtLoginChange={() => {}}
			onPreferencesChange={() => {}}
		/>,
	);
}

describe("SettingsPanel", () => {
	it("renders labeled fieldsets for startup, font, and theme controls", () => {
		// Given current companion preferences and launch-at-login status
		// When the settings panel is rendered
		const html = renderSettingsPanel();

		// Then semantic groups, labels, and fixed choices are visible
		expect(html).toContain("<fieldset");
		expect(html).toContain("<h2>Settings</h2>");
		expect(html).toContain("<legend>Startup</legend>");
		expect(html).toContain("<legend>Font</legend>");
		expect(html).toContain("<legend>Theme</legend>");
		expect(html).toContain('for="launch-at-login"');
		expect(html).toContain('for="companion-font"');
		expect(html).toContain("Launch at login");
		expect(html).toContain("System Mono");
		expect(html).toContain("JetBrains Mono");
		expect(html).toContain("Dracula");
		expect(html).toContain("Nord");
		expect(html).toContain("Solarized");
		expect(html).toContain("Gruvbox");
		expect(html).toContain("Light");
		expect(html).toContain("Dark");
		expect(html).toContain("System");
		expect(html).toContain("System (Dark now)");
		expect(html).not.toContain('id="companion-theme"');
	});

	it("shows the selected font in a live preview sample", () => {
		// Given Menlo is the selected companion font
		const html = renderSettingsPanel({
			currentPreferences: {
				font: "menlo",
				themeFamily: "dracula",
				themeMode: "system",
			},
		});

		// When the settings panel is rendered
		// Then the sample text uses the selected font family
		expect(html).toContain('class="font-preview"');
		expect(html).toContain("font-family:Menlo");
		expect(html).toContain("workbranch feat/update-0619");
		expect(html).toContain("1234567890");
	});

	it("renders only four large theme buttons for the selected dark or light mode", () => {
		// Given the Nord Light theme is selected
		const html = renderSettingsPanel({
			currentPreferences: {
				font: "system-mono",
				themeFamily: "nord",
				themeMode: "light",
			},
		});

		// When settings are rendered
		// Then theme choices are large button cards only for the resolved light mode
		expect(html).toContain('class="theme-button-grid"');
		expect(html).toContain('class="theme-button"');
		expect(html).toContain("theme-swatch theme-swatch-dracula-light");
		expect(html).toContain("theme-swatch theme-swatch-nord-light");
		expect(html).not.toContain("theme-swatch theme-swatch-dracula-dark");
		expect(html).not.toContain("theme-swatch theme-swatch-nord-dark");
		expect(html).toContain('aria-pressed="true"');
		expect(html).toContain("Current theme: Nord Light");
		expect(html).not.toContain('<select id="companion-theme"');
	});

	it("renders representative color chips instead of a single gradient bar", () => {
		// Given light mode theme choices are visible
		const html = renderSettingsPanel({
			currentPreferences: {
				font: "system-mono",
				themeFamily: "nord",
				themeMode: "light",
			},
		});

		// When the four theme cards are rendered
		// Then each theme card exposes four representative color chips
		expect(html.match(/class="theme-swatch-color"/g)).toHaveLength(16);
		expect(html).toContain(
			'class="theme-swatch theme-swatch-dracula-light"><span class="theme-swatch-color"',
		);
	});

	it("renders system mode using the current system dark or light theme", () => {
		// Given system mode is selected while the OS is currently light
		const html = renderSettingsPanel({
			currentPreferences: preferences,
			systemThemeMode: "light",
		});

		// When settings are rendered
		// Then only light theme family buttons are shown under system mode
		expect(html).toContain("System (Light now)");
		expect(html).toContain("theme-swatch theme-swatch-dracula-light");
		expect(html).not.toContain("theme-swatch theme-swatch-dracula-dark");
		expect(html).toContain("Current theme: Dracula Light");
	});

	it("delegates launch, font, and theme updates to app-shell callbacks", () => {
		// Given a rendered settings panel with callback spies
		const launchCalls: boolean[] = [];
		const preferenceCalls: CompanionPreferences[] = [];
		const element = SettingsPanel({
			preferences,
			systemThemeMode: "dark",
			launchAtLogin: false,
			launchAtLoginLoading: false,
			onLaunchAtLoginChange: (enabled) => {
				launchCalls.push(enabled);
			},
			onPreferencesChange: (next) => {
				preferenceCalls.push(next);
			},
		});

		// When controls change
		const launchToggle = collectByType<InputProps>(element, "input").find(
			(input) => input.id === "launch-at-login",
		);
		const selects = collectByType<SelectProps>(element, "select");
		const buttons = collectByType<ButtonProps>(element, "button");
		const fontSelect = selects.find((select) => select.id === "companion-font");
		const modeButton = buttons.find(
			(button) => button["aria-label"] === "Use Light theme mode",
		);
		const themeButton = buttons.find(
			(button) => button["aria-label"] === "Use Nord theme",
		);
		launchToggle?.onChange?.({ currentTarget: { checked: true } });
		fontSelect?.onChange?.({
			currentTarget: { value: "menlo" satisfies CompanionFont },
		});
		modeButton?.onClick?.();
		themeButton?.onClick?.();

		// Then the app shell receives every change without the panel swallowing failures
		expect(launchCalls).toEqual([true]);
		expect(preferenceCalls).toEqual([
			{ font: "menlo", themeFamily: "dracula", themeMode: "system" },
			{ font: "system-mono", themeFamily: "dracula", themeMode: "light" },
			{ font: "system-mono", themeFamily: "nord", themeMode: "system" },
		]);
	});
});
