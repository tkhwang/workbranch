import { Children, isValidElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import {
	DEFAULT_MENU_BAR,
	type MenuBarConfig,
} from "../src/application/menuBar";
import type {
	CompanionFont,
	CompanionFontSize,
	CompanionPreferences,
	CompanionTheme,
} from "../src/application/preferences";
import { AgentThemePicker } from "../src/ui/AgentThemePicker";
import { MenuBarSettings } from "../src/ui/MenuBarSettings";
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

type TraversableProps = {
	readonly children?: ReactNode;
};

type MenuBarPickerProps = {
	readonly value: MenuBarConfig;
	readonly onChange: (config: MenuBarConfig) => void;
};

type ThemePickerProps = {
	readonly value: CompanionTheme;
	readonly onChange: (theme: CompanionTheme) => void;
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

function findThemePicker(node: ReactNode): ThemePickerProps | undefined {
	let result: ThemePickerProps | undefined;
	const visit = (child: ReactNode): void => {
		if (!isValidElement<ThemePickerProps & TraversableProps>(child)) {
			return;
		}
		if (child.type === AgentThemePicker) {
			result = child.props;
		}
		Children.forEach(child.props.children, visit);
	};
	visit(node);
	return result;
}

function findMenuBarPicker(node: ReactNode): MenuBarPickerProps | undefined {
	let result: MenuBarPickerProps | undefined;
	const visit = (child: ReactNode): void => {
		if (!isValidElement<MenuBarPickerProps & TraversableProps>(child)) {
			return;
		}
		if (child.type === MenuBarSettings) {
			result = child.props;
		}
		Children.forEach(child.props.children, visit);
	};
	visit(node);
	return result;
}

const preferences: CompanionPreferences = {
	font: "system-mono",
	fontSize: "medium",
	theme: "claude",
	menuBar: DEFAULT_MENU_BAR,
};

function renderSettingsPanel({
	currentPreferences = preferences,
	launchAtLoginLoading = false,
}: {
	readonly currentPreferences?: CompanionPreferences;
	readonly launchAtLoginLoading?: boolean;
} = {}): string {
	return renderToStaticMarkup(
		<SettingsPanel
			claudeLimitRelay={{
				status: { enabled: false, previousCommand: null },
				loading: false,
				onChange: () => undefined,
			}}
			preferences={currentPreferences}
			launchAtLogin={false}
			launchAtLoginLoading={launchAtLoginLoading}
			onLaunchAtLoginChange={() => undefined}
			onPreferencesChange={() => undefined}
		/>,
	);
}

describe("SettingsPanel", () => {
	it("renders Claude terminal panels and exactly two agent themes", () => {
		const html = renderSettingsPanel();

		expect(html).toContain('data-terminal-panel="claude"');
		expect(html).toContain('data-terminal-panel-anatomy="claude"');
		expect(html).toContain("<fieldset");
		expect(html).toContain("<legend>Startup</legend>");
		expect(html).toContain("<legend>Claude Limits</legend>");
		expect(html).toContain('for="claude-limit-relay"');
		expect(html).toContain("<legend>Menu Bar</legend>");
		expect(html).toContain("<legend>Font</legend>");
		expect(html).toContain("<legend>Text Size</legend>");
		expect(html).toContain("<legend>Theme</legend>");
		expect(html).not.toContain("Weekly Limits");
		expect(html).toContain('aria-label="Menu bar items"');
		expect(html).toContain('for="launch-at-login"');
		expect(html).toContain('for="companion-font"');
		expect(html).toContain('for="companion-font-size"');
		expect(html).toContain("Open at Login");
		expect(html).toContain("System Mono");
		expect(html).toContain("JetBrains Mono");
		expect(html).toContain("Extra Large");
		expect(html).toContain("Claude Code");
		expect(html).toContain("Codex");
		// Four menu bar items, two percent bases and two themes are the only buttons.
		expect(html.match(/<button/g)).toHaveLength(8);
		expect(html).not.toContain(">Light</button>");
		expect(html).not.toContain(">Dark</button>");
		expect(html).not.toContain(">System</button>");
		expect(html).not.toContain("theme mode");
	});

	it("renders Codex settings with Claude fieldset sections", () => {
		const html = renderSettingsPanel({
			currentPreferences: {
				font: "menlo",
				fontSize: "medium",
				theme: "codex",
				menuBar: DEFAULT_MENU_BAR,
			},
		});

		expect(html).toContain('data-terminal-panel="codex"');
		expect(html).toContain('data-terminal-panel-anatomy="claude"');
		expect(html).toContain("<fieldset");
		expect(html).toContain("<legend>Startup</legend>");
		expect(html).toContain("<legend>Font</legend>");
		expect(html).toContain("<legend>Text Size</legend>");
		expect(html).toContain("<legend>Theme</legend>");
		expect(html).not.toContain('class="terminal-panel-heading"');
		expect(html).toContain('aria-label="Use Codex theme"');
		expect(html).toContain('aria-pressed="true"');
	});

	it("shows the selected font in a live preview sample", () => {
		const html = renderSettingsPanel({
			currentPreferences: {
				font: "menlo",
				fontSize: "medium",
				theme: "claude",
				menuBar: DEFAULT_MENU_BAR,
			},
		});

		expect(html).toContain('class="font-preview"');
		expect(html).toContain("font-family:Menlo");
		expect(html).toContain("workbranch feat/update-0619");
		expect(html).toContain("1234567890");
	});

	it("previews the smallest scaled copy alongside the selected text size", () => {
		const html = renderSettingsPanel({
			currentPreferences: {
				font: "menlo",
				fontSize: "large",
				theme: "claude",
				menuBar: DEFAULT_MENU_BAR,
			},
		});

		expect(html).toContain("Preview · Large");
		expect(html).toContain('class="font-preview-meta"');
		expect(html).toContain("ci: build signed macOS DMGs · 11d");
		expect(html).toContain('value="large"');
	});

	it("disables launch-at-login while its state is loading", () => {
		const html = renderSettingsPanel({ launchAtLoginLoading: true });

		expect(html).toContain('id="launch-at-login"');
		expect(html).toContain('disabled=""');
		expect(html).toContain("Checking login item state");
	});

	it("delegates launch, font, size, and theme updates to app-shell callbacks", () => {
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
		});
		const launchToggle = collectByType<InputProps>(element, "input").find(
			(input) => input.id === "launch-at-login",
		);
		const selects = collectByType<SelectProps>(element, "select");
		const fontSelect = selects.find((select) => select.id === "companion-font");
		const fontSizeSelect = selects.find(
			(select) => select.id === "companion-font-size",
		);
		const themePicker = findThemePicker(element);

		launchToggle?.onChange?.({ currentTarget: { checked: true } });
		fontSelect?.onChange?.({
			currentTarget: { value: "menlo" satisfies CompanionFont },
		});
		fontSizeSelect?.onChange?.({
			currentTarget: { value: "large" satisfies CompanionFontSize },
		});
		themePicker?.onChange("codex");

		expect(launchCalls).toEqual([true]);
		expect(preferenceCalls).toEqual([
			{
				font: "menlo",
				fontSize: "medium",
				theme: "claude",
				menuBar: DEFAULT_MENU_BAR,
			},
			{
				font: "system-mono",
				fontSize: "large",
				theme: "claude",
				menuBar: DEFAULT_MENU_BAR,
			},
			{
				font: "system-mono",
				fontSize: "medium",
				theme: "codex",
				menuBar: DEFAULT_MENU_BAR,
			},
		]);
	});

	it("delegates the edited menu bar config", () => {
		const preferenceCalls: CompanionPreferences[] = [];
		const element = SettingsPanel({
			preferences,
			launchAtLogin: false,
			launchAtLoginLoading: false,
			onLaunchAtLoginChange: () => undefined,
			onPreferencesChange: (next) => {
				preferenceCalls.push(next);
			},
		});
		const edited = { ...DEFAULT_MENU_BAR, todayTokens: false };
		findMenuBarPicker(element)?.onChange(edited);

		expect(preferenceCalls).toEqual([{ ...preferences, menuBar: edited }]);
	});

	it("ignores a text size the preference contract does not know", () => {
		const preferenceCalls: CompanionPreferences[] = [];
		const element = SettingsPanel({
			preferences,
			launchAtLogin: false,
			launchAtLoginLoading: false,
			onLaunchAtLoginChange: () => undefined,
			onPreferencesChange: (next) => {
				preferenceCalls.push(next);
			},
		});
		const fontSizeSelect = collectByType<SelectProps>(element, "select").find(
			(select) => select.id === "companion-font-size",
		);

		fontSizeSelect?.onChange?.({ currentTarget: { value: "gigantic" } });

		expect(preferenceCalls).toEqual([]);
	});
});

describe("MenuBarSettings", () => {
	function render(value: MenuBarConfig): string {
		return renderToStaticMarkup(
			<MenuBarSettings value={value} onChange={() => undefined} />,
		);
	}

	it("previews every item as used percent by default", () => {
		const html = render(DEFAULT_MENU_BAR);

		expect(html).toContain(">CL 5h 42% · W 63%  CO W 18% · 31.0M<");
		expect(html.match(/aria-pressed="true"/g)).toHaveLength(5);
		expect(html).toContain("5-hour limit, CL 5h");
		expect(html).toContain("7-day limit, CO W");
		expect(html).toContain("Both agents since midnight");
	});

	it("previews remaining percent and only the picked items", () => {
		const html = render({
			...DEFAULT_MENU_BAR,
			claude5h: false,
			todayTokens: false,
			percent: "remaining",
		});

		expect(html).toContain(">CL W 37%  CO W 82%<");
		expect(html).toContain(
			'aria-label="Show Claude 5h in the menu bar" aria-pressed="false"',
		);
	});

	it("shows the icon alone and disables the percent switch with nothing picked", () => {
		const html = render({
			...DEFAULT_MENU_BAR,
			claude5h: false,
			claudeWeekly: false,
			codexWeekly: false,
			todayTokens: false,
		});

		expect(html).not.toContain("menu-bar-sample-text");
		expect(html).toContain("the menu bar shows the icon alone");
		expect(html).toMatch(
			/<fieldset[^>]*aria-label="Limit percent"[^>]*disabled/,
		);
	});

	it("toggles one item and keeps the rest", () => {
		const calls: MenuBarConfig[] = [];
		const element = MenuBarSettings({
			value: DEFAULT_MENU_BAR,
			onChange: (next) => {
				calls.push(next);
			},
		});
		const buttons = collectByType<{
			readonly "aria-label"?: string;
			readonly onClick?: () => void;
		}>(element, "button");
		buttons
			.find(
				(button) =>
					button["aria-label"] === "Show Codex weekly in the menu bar",
			)
			?.onClick?.();
		buttons
			.find((button) => button["aria-label"] === "Show limits as Remaining %")
			?.onClick?.();

		expect(calls).toEqual([
			{ ...DEFAULT_MENU_BAR, codexWeekly: false },
			{ ...DEFAULT_MENU_BAR, percent: "remaining" },
		]);
	});
});
