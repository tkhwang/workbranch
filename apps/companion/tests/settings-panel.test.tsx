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
	themeFamily: "companion",
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
	it("renders labeled fieldsets for startup, font, and mode controls", () => {
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
		expect(html).toContain("Open at Login");
		expect(html).toContain("System Mono");
		expect(html).toContain("JetBrains Mono");
		expect(html).toContain("Light");
		expect(html).toContain("Dark");
		expect(html).toContain("System");
		expect(html).toContain("System (Dark now)");
		expect(html).toContain("Palette: Catppuccin Dark / White Light");
		expect(html).not.toContain('id="companion-theme"');
	});

	it("shows the selected font in a live preview sample", () => {
		// Given Menlo is the selected companion font
		const html = renderSettingsPanel({
			currentPreferences: {
				font: "menlo",
				themeFamily: "companion",
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

	it("renders only the theme mode toggle without color family cards", () => {
		// Given explicit light mode is selected
		const html = renderSettingsPanel({
			currentPreferences: {
				font: "system-mono",
				themeFamily: "companion",
				themeMode: "light",
			},
		});

		// When settings are rendered
		// Then the color-family grid and swatches are absent
		expect(html).toContain("Light mode");
		expect(html).toContain("Palette: Catppuccin Dark / White Light");
		expect(html).not.toContain('class="theme-button-grid"');
		expect(html).not.toContain('class="theme-button"');
		expect(html).not.toContain("theme-swatch");
		expect(html).not.toContain("Use GitHub theme");
		expect(html).not.toContain("Current theme:");
	});

	it("renders system mode using the current system dark or light mode", () => {
		// Given system mode is selected while the OS is currently light
		const html = renderSettingsPanel({
			currentPreferences: preferences,
			systemThemeMode: "light",
		});

		// When settings are rendered
		// Then mode state is visible without exposing color-family choices
		expect(html).toContain("System (Light now)");
		expect(html).not.toContain("theme-swatch");
	});

	it("delegates launch, font, and mode updates to app-shell callbacks", () => {
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
		launchToggle?.onChange?.({ currentTarget: { checked: true } });
		fontSelect?.onChange?.({
			currentTarget: { value: "menlo" satisfies CompanionFont },
		});
		modeButton?.onClick?.();

		// Then the app shell receives every change without the panel swallowing failures
		expect(launchCalls).toEqual([true]);
		expect(preferenceCalls).toEqual([
			{ font: "menlo", themeFamily: "companion", themeMode: "system" },
			{ font: "system-mono", themeFamily: "companion", themeMode: "light" },
		]);
	});
});
