import { Children, isValidElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import type {
	CompanionFont,
	CompanionFontSize,
	CompanionPreferences,
	CompanionTheme,
} from "../src/application/preferences";
import { AgentThemePicker } from "../src/ui/AgentThemePicker";
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

const preferences: CompanionPreferences = {
	font: "system-mono",
	fontSize: "medium",
	theme: "claude",
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
		expect(html).toContain("<legend>Font</legend>");
		expect(html).toContain("<legend>Text Size</legend>");
		expect(html).toContain("<legend>Theme</legend>");
		expect(html).toContain('for="launch-at-login"');
		expect(html).toContain('for="companion-font"');
		expect(html).toContain('for="companion-font-size"');
		expect(html).toContain("Open at Login");
		expect(html).toContain("System Mono");
		expect(html).toContain("JetBrains Mono");
		expect(html).toContain("Extra Large");
		expect(html).toContain("Claude Code");
		expect(html).toContain("Codex");
		expect(html.match(/<button/g)).toHaveLength(2);
		expect(html).not.toContain(">Light</button>");
		expect(html).not.toContain(">Dark</button>");
		expect(html).not.toContain(">System</button>");
		expect(html).not.toContain("theme mode");
	});

	it("renders Codex settings with Claude fieldset sections", () => {
		const html = renderSettingsPanel({
			currentPreferences: { font: "menlo", fontSize: "medium", theme: "codex" },
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
			},
		});

		expect(html).toContain('class="font-preview"');
		expect(html).toContain("font-family:Menlo");
		expect(html).toContain("workbranch feat/update-0619");
		expect(html).toContain("1234567890");
	});

	it("previews the smallest scaled copy alongside the selected text size", () => {
		const html = renderSettingsPanel({
			currentPreferences: { font: "menlo", fontSize: "large", theme: "claude" },
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
			{ font: "menlo", fontSize: "medium", theme: "claude" },
			{ font: "system-mono", fontSize: "large", theme: "claude" },
			{ font: "system-mono", fontSize: "medium", theme: "codex" },
		]);
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
