import {
	Children,
	isValidElement,
	type JSXElementConstructor,
	type ReactNode,
} from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import {
	DEFAULT_IDE_WINDOW,
	type IdeWindowConfig,
} from "../src/application/ideWindow";
import {
	DEFAULT_MENU_BAR,
	type MenuBarConfig,
} from "../src/application/menuBar";
import type {
	CompanionFont,
	CompanionPreferences,
	CompanionTheme,
} from "../src/application/preferences";
import { DEFAULT_SCREENSAVER } from "../src/application/screensaver";
import { AgentThemePicker } from "../src/ui/AgentThemePicker";
import {
	type IdeWindowAccessProps,
	IdeWindowSettings,
} from "../src/ui/IdeWindowSettings";
import { MenuBarSettings } from "../src/ui/MenuBarSettings";
import { SegmentedControl } from "../src/ui/SettingsLayout";
import {
	type SettingsCategory,
	SettingsNav,
	settingsEyebrow,
} from "../src/ui/SettingsNav";
import {
	type PreferenceCategory,
	SettingsPanel,
} from "../src/ui/SettingsPanel";
import { SettingsView } from "../src/ui/SettingsView";

type InputProps = {
	readonly id?: string;
	readonly checked?: boolean;
	readonly onChange?: (event: {
		readonly currentTarget: { readonly checked: boolean };
	}) => void;
};

type SelectProps = {
	readonly id?: string;
	readonly onChange?: (event: {
		readonly currentTarget: { readonly value: string };
	}) => void;
};

type ButtonProps = {
	readonly children?: ReactNode;
	readonly onClick?: () => void;
};

type SegmentedProps = {
	readonly label: string;
	readonly onChange: (value: string) => void;
};

type TraversableProps = {
	readonly children?: ReactNode;
};

/** Walks the returned element tree through `children`, without rendering. */
function collect<TProps>(
	node: ReactNode,
	type: string | JSXElementConstructor<never>,
): readonly TProps[] {
	const found: TProps[] = [];
	const visit = (child: ReactNode): void => {
		if (!isValidElement<TProps & TraversableProps>(child)) return;
		if (child.type === type) found.push(child.props);
		Children.forEach(child.props.children, visit);
	};
	visit(node);
	return found;
}

function segmented(node: ReactNode, label: string): SegmentedProps | undefined {
	return collect<SegmentedProps>(node, SegmentedControl).find(
		(props) => props.label === label,
	);
}

const preferences: CompanionPreferences = {
	font: "system-mono",
	fontSize: "medium",
	theme: "claude",
	menuBar: DEFAULT_MENU_BAR,
	screensaver: DEFAULT_SCREENSAVER,
	ideWindow: DEFAULT_IDE_WINDOW,
};

const relay = {
	status: { enabled: false, previousCommand: null },
	loading: false,
	onChange: () => undefined,
};

function access(
	granted: boolean | undefined,
	calls: string[] = [],
): IdeWindowAccessProps {
	return {
		granted,
		loading: false,
		onRequest: () => calls.push("request"),
		onOpenSettings: () => calls.push("open settings"),
	};
}

function panelProps(
	category: PreferenceCategory,
	overrides: {
		readonly preferences?: CompanionPreferences;
		readonly launchAtLoginLoading?: boolean;
		readonly onLaunchAtLoginChange?: (enabled: boolean) => void;
		readonly onPreferencesChange?: (next: CompanionPreferences) => void;
		readonly ideWindowAccess?: IdeWindowAccessProps;
	} = {},
) {
	return {
		category,
		claudeLimitRelay: relay,
		ideWindowAccess: overrides.ideWindowAccess ?? access(true),
		preferences: overrides.preferences ?? preferences,
		launchAtLogin: false,
		launchAtLoginLoading: overrides.launchAtLoginLoading ?? false,
		onLaunchAtLoginChange: overrides.onLaunchAtLoginChange ?? (() => undefined),
		onPreferencesChange: overrides.onPreferencesChange ?? (() => undefined),
		onScreensaverPreview: () => undefined,
	};
}

function renderPage(
	category: PreferenceCategory,
	overrides: Parameters<typeof panelProps>[1] = {},
): string {
	return renderToStaticMarkup(
		<SettingsPanel {...panelProps(category, overrides)} />,
	);
}

describe("SettingsPanel", () => {
	it("opens General with the status slot first, then startup and limit switches", () => {
		const html = renderToStaticMarkup(
			<SettingsPanel {...panelProps("general")} status={<p>STATUS SLOT</p>} />,
		);

		expect(html).toContain('aria-label="01 · General"');
		expect(html).toContain("<h2>Status, startup and limits</h2>");
		expect(html.indexOf("STATUS SLOT")).toBeLessThan(
			html.indexOf("Open at Login"),
		);
		expect(html).toContain('aria-label="Startup"');
		expect(html).toContain('aria-label="IDE Windows"');
		expect(html).toContain('aria-label="Claude Limits"');
		expect(html).toContain('for="launch-at-login"');
		expect(html).toContain('for="ide-window-enabled"');
		expect(html).toContain('for="claude-limit-relay"');
		expect(html.indexOf('aria-label="Startup"')).toBeLessThan(
			html.indexOf('aria-label="IDE Windows"'),
		);
		expect(html.match(/role="switch"/g)).toHaveLength(3);
		expect(html).not.toContain("<legend");
		expect(html).not.toContain("terminal-panel");
	});

	it("gives every preference page its numbered heading", () => {
		const pages: readonly [PreferenceCategory, string, string][] = [
			["menu-bar", "03 · Menu Bar", "What the menu bar shows"],
			["screen-saver", "04 · Screen Saver", "Dashboard while agents work"],
			["appearance", "05 · Appearance", "Theme, font and text size"],
		];
		for (const [category, eyebrow, title] of pages) {
			const html = renderPage(category);
			expect(html).toContain(`<p class="settings-page-eyebrow">${eyebrow}</p>`);
			expect(html).toContain(`<h2>${title}</h2>`);
		}
	});

	it("offers exactly the two agent themes as a segmented control", () => {
		const html = renderPage("appearance", {
			preferences: { ...preferences, theme: "codex" },
		});

		expect(html).toContain('aria-label="Agent theme"');
		expect(html).toContain('aria-label="Use Claude Code theme"');
		expect(html).toMatch(/aria-label="Use Codex theme" aria-pressed="true"/);
		expect(html).not.toContain(">Light</button>");
		expect(html).not.toContain(">Dark</button>");
		expect(html).not.toContain(">System</button>");
	});

	it("previews the selected font and text size together", () => {
		const html = renderPage("appearance", {
			preferences: { ...preferences, font: "menlo", fontSize: "large" },
		});

		expect(html).toContain('class="font-preview"');
		expect(html).toContain("font-family:Menlo");
		expect(html).toContain("Preview · Menlo · Large");
		expect(html).toContain("workbranch feat/update-0619");
		expect(html).toContain("1234567890");
		expect(html).toContain('class="font-preview-meta"');
		expect(html).toContain("ci: build signed macOS DMGs · 11d");
		expect(html).toContain("System Mono");
		expect(html).toContain("JetBrains Mono");
		expect(html).toContain('aria-label="Text size"');
		expect(html).toMatch(/aria-pressed="true"[^>]*>Large<\/button>/);
		expect(html).toContain(">Extra Large</button>");
	});

	it("disables launch-at-login while its state is loading", () => {
		const html = renderPage("general", { launchAtLoginLoading: true });

		expect(html).toMatch(/disabled=""[^>]*id="launch-at-login"/);
		expect(html).toContain("Checking login item state");
	});

	it("delegates launch, font, size, and theme updates to app-shell callbacks", () => {
		const launchCalls: boolean[] = [];
		const preferenceCalls: CompanionPreferences[] = [];
		const overrides = {
			onLaunchAtLoginChange: (enabled: boolean) => {
				launchCalls.push(enabled);
			},
			onPreferencesChange: (next: CompanionPreferences) => {
				preferenceCalls.push(next);
			},
		};
		const general = SettingsPanel(panelProps("general", overrides));
		const appearance = SettingsPanel(panelProps("appearance", overrides));

		collect<InputProps>(general, "input")
			.find((input) => input.id === "launch-at-login")
			?.onChange?.({ currentTarget: { checked: true } });
		collect<SelectProps>(appearance, "select")
			.find((select) => select.id === "companion-font")
			?.onChange?.({
				currentTarget: { value: "menlo" satisfies CompanionFont },
			});
		segmented(appearance, "Text size")?.onChange("large");
		collect<{ readonly onChange: (theme: CompanionTheme) => void }>(
			appearance,
			AgentThemePicker,
		)[0]?.onChange("codex");

		expect(launchCalls).toEqual([true]);
		expect(preferenceCalls).toEqual([
			{ ...preferences, font: "menlo" },
			{ ...preferences, fontSize: "large" },
			{ ...preferences, theme: "codex" },
		]);
	});

	it("ignores a font the preference contract does not know", () => {
		const preferenceCalls: CompanionPreferences[] = [];
		const appearance = SettingsPanel(
			panelProps("appearance", {
				onPreferencesChange: (next) => {
					preferenceCalls.push(next);
				},
			}),
		);

		collect<SelectProps>(appearance, "select")
			.find((select) => select.id === "companion-font")
			?.onChange?.({ currentTarget: { value: "comic-sans" } });

		expect(preferenceCalls).toEqual([]);
	});

	it("delegates the edited menu bar config", () => {
		const preferenceCalls: CompanionPreferences[] = [];
		const element = SettingsPanel(
			panelProps("menu-bar", {
				onPreferencesChange: (next) => {
					preferenceCalls.push(next);
				},
			}),
		);
		const edited = { ...DEFAULT_MENU_BAR, todayTokens: false };
		collect<{ readonly onChange: (config: MenuBarConfig) => void }>(
			element,
			MenuBarSettings,
		)[0]?.onChange(edited);

		expect(preferenceCalls).toEqual([{ ...preferences, menuBar: edited }]);
	});
});

describe("IdeWindowSettings", () => {
	function render(
		value: IdeWindowConfig,
		granted: boolean | undefined,
		loading = false,
	): string {
		return renderToStaticMarkup(
			<IdeWindowSettings
				{...access(granted)}
				loading={loading}
				onChange={() => undefined}
				value={value}
			/>,
		);
	}

	it("starts switched off and leaves window placement to the IDE", () => {
		const html = render(DEFAULT_IDE_WINDOW, false);

		expect(html).toMatch(/id="ide-window-enabled"(?![^>]*checked)/);
		expect(html).toContain("open a new window where they choose");
		expect(html).not.toContain("Open System Settings");
	});

	it("explains the move once the switch is on and access is granted", () => {
		const html = render({ enabled: true }, true);

		expect(html).toMatch(/id="ide-window-enabled"[^>]*checked=""/);
		expect(html).toContain("moves to the middle of the screen Companion is on");
		expect(html).not.toContain("Open System Settings");
	});

	it("offers System Settings while the switch waits for access", () => {
		const html = render({ enabled: true }, false);

		expect(html).toContain("Waiting for the Accessibility permission");
		expect(html).toContain("Privacy &amp; Security › Accessibility");
		expect(html).toContain(">Open System Settings</button>");
	});

	it("says when the permission is still being read", () => {
		expect(render({ enabled: true }, undefined, true)).toContain(
			"Checking the Accessibility permission",
		);
	});

	it("asks macOS for access when switched on without it", () => {
		const changes: IdeWindowConfig[] = [];
		const calls: string[] = [];
		const element = IdeWindowSettings({
			...access(false, calls),
			onChange: (config) => changes.push(config),
			value: DEFAULT_IDE_WINDOW,
		});
		collect<InputProps>(element, "input")
			.find((input) => input.id === "ide-window-enabled")
			?.onChange?.({ currentTarget: { checked: true } });

		expect(changes).toEqual([{ enabled: true }]);
		expect(calls).toEqual(["request"]);
	});

	it("does not ask again when access is granted or the switch turns off", () => {
		const calls: string[] = [];
		for (const [granted, value, checked] of [
			[true, DEFAULT_IDE_WINDOW, true],
			[false, { enabled: true }, false],
		] as const) {
			const element = IdeWindowSettings({
				...access(granted, calls),
				onChange: () => undefined,
				value,
			});
			collect<InputProps>(element, "input")
				.find((input) => input.id === "ide-window-enabled")
				?.onChange?.({ currentTarget: { checked } });
		}

		expect(calls).toEqual([]);
	});

	it("opens System Settings from the waiting row", () => {
		const calls: string[] = [];
		const element = IdeWindowSettings({
			...access(false, calls),
			onChange: () => undefined,
			value: { enabled: true },
		});
		collect<ButtonProps>(element, "button")[0]?.onClick?.();

		expect(calls).toEqual(["open settings"]);
	});

	it("saves the switch through the General page", () => {
		const preferenceCalls: CompanionPreferences[] = [];
		const general = SettingsPanel(
			panelProps("general", {
				onPreferencesChange: (next) => {
					preferenceCalls.push(next);
				},
			}),
		);
		collect<{ readonly onChange: (config: IdeWindowConfig) => void }>(
			general,
			IdeWindowSettings,
		)[0]?.onChange({ enabled: true });

		expect(preferenceCalls).toEqual([
			{ ...preferences, ideWindow: { enabled: true } },
		]);
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
		expect(html.match(/aria-checked="true"/g)).toHaveLength(4);
		expect(html).toMatch(/aria-pressed="true"[^>]*>Used %<\/button>/);
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
			'aria-checked="false" aria-label="Show Claude 5h in the menu bar"',
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
		collect<InputProps>(element, "input")
			.find((input) => input.id === "menu-bar-codexWeekly")
			?.onChange?.({ currentTarget: { checked: false } });
		segmented(element, "Limit percent")?.onChange("remaining");

		expect(calls).toEqual([
			{ ...DEFAULT_MENU_BAR, codexWeekly: false },
			{ ...DEFAULT_MENU_BAR, percent: "remaining" },
		]);
	});
});

describe("SettingsView", () => {
	function render(
		category: SettingsCategory,
		attention: Partial<Record<SettingsCategory, boolean>> = {},
	): string {
		return renderToStaticMarkup(
			<SettingsView
				{...panelProps("general")}
				attention={attention}
				category={category}
				connections={<p>CONNECTIONS PANEL</p>}
				onCategoryChange={() => undefined}
				status={<p>STATUS SLOT</p>}
			/>,
		);
	}

	it("shows the category tabs and only the current page", () => {
		const html = render("menu-bar");

		expect(html).toContain('aria-label="Settings categories"');
		// Setup comes right after General, whose status links to it.
		const order = [
			"General",
			"Connections",
			"Menu Bar",
			"Screen Saver",
			"Appearance",
		].map((label) => html.indexOf(`<span>${label}</span>`));
		expect(order.every((index) => index >= 0)).toBe(true);
		expect(order).toEqual([...order].sort((a, b) => a - b));
		expect(settingsEyebrow("connections")).toBe("02 · Connections");
		expect(html.match(/aria-current="page"/g)).toHaveLength(1);
		expect(html).toMatch(/aria-current="page"[^>]*>.*?<span>Menu Bar<\/span>/);
		expect(html).toContain("03 · Menu Bar");
		expect(html).not.toContain("01 · General");
		expect(html).not.toContain("STATUS SLOT");
		expect(html).not.toContain("CONNECTIONS PANEL");
	});

	it("puts status on General and the connections panel on its own tab", () => {
		expect(render("general")).toContain("STATUS SLOT");
		const connections = render("connections");
		expect(connections).toContain("CONNECTIONS PANEL");
		expect(connections).not.toContain("STATUS SLOT");
	});

	it("marks only the tabs that need attention", () => {
		const html = render("appearance", { general: true, connections: false });

		expect(html).toContain('aria-label="General, needs attention"');
		expect(html.match(/settings-nav-dot/g)).toHaveLength(1);
	});

	it("reports the picked tab", () => {
		const picked: SettingsCategory[] = [];
		const nav = SettingsNav({
			current: "general",
			attention: {},
			onChange: (category) => picked.push(category),
		});
		collect<ButtonProps>(nav, "button")
			.find((button) =>
				Children.toArray(button.children).some(
					(child) =>
						isValidElement<TraversableProps>(child) &&
						child.props.children === "Connections",
				),
			)
			?.onClick?.();

		expect(picked).toEqual(["connections"]);
	});
});
