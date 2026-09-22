import { readFileSync } from "node:fs";
import { Children, isValidElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import {
	type LimitAccount,
	type LimitAccounts,
	MAX_LIMIT_ACCOUNTS,
	newLimitAccount,
} from "../src/application/limits";
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

type TextInputProps = {
	readonly id?: string;
	readonly value?: string;
	readonly onChange?: (event: {
		readonly currentTarget: { readonly value: string };
	}) => void;
};

type ButtonProps = {
	readonly className?: string;
	readonly disabled?: boolean;
	readonly "aria-label"?: string;
	readonly onClick?: () => void;
};

// 2026-09-22 (Tue) 14:37 local
const settingsNow = new Date(2026, 8, 22, 14, 37, 0, 0);

function limitAccount(
	id: string,
	label: string,
	nextResetAt: number,
): LimitAccount {
	return { id, label, nextResetAt };
}

function localEpoch(
	year: number,
	month: number,
	day: number,
	hour = 0,
	minute = 0,
): number {
	return Math.floor(
		new Date(year, month - 1, day, hour, minute, 0, 0).getTime() / 1000,
	);
}

function renderSettingsPanel({
	accounts = [],
	currentPreferences = preferences,
	launchAtLoginLoading = false,
}: {
	readonly accounts?: LimitAccounts;
	readonly currentPreferences?: CompanionPreferences;
	readonly launchAtLoginLoading?: boolean;
} = {}): string {
	return renderToStaticMarkup(
		<SettingsPanel
			accounts={accounts}
			preferences={currentPreferences}
			launchAtLogin={false}
			launchAtLoginLoading={launchAtLoginLoading}
			now={() => settingsNow}
			onAccountsChange={() => undefined}
			onLaunchAtLoginChange={() => undefined}
			onPreferencesChange={() => undefined}
		/>,
	);
}

function settingsPanelElement(
	accounts: LimitAccounts,
	onAccountsChange: (next: LimitAccounts) => void,
): ReactNode {
	return SettingsPanel({
		accounts,
		preferences,
		launchAtLogin: false,
		launchAtLoginLoading: false,
		now: () => settingsNow,
		createId: () => "created-id",
		onAccountsChange,
		onLaunchAtLoginChange: () => undefined,
		onPreferencesChange: () => undefined,
	});
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
		expect(html).toContain("<legend>Weekly Limits</legend>");
		expect(html).toContain('for="launch-at-login"');
		expect(html).toContain('for="companion-font"');
		expect(html).toContain('for="companion-font-size"');
		expect(html).toContain("Open at Login");
		expect(html).toContain("System Mono");
		expect(html).toContain("JetBrains Mono");
		expect(html).toContain("Extra Large");
		expect(html).toContain("Claude Code");
		expect(html).toContain("Codex");
		// Two theme buttons plus the weekly-limits add button.
		expect(html.match(/<button/g)).toHaveLength(3);
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
			accounts: [],
			preferences,
			launchAtLogin: false,
			launchAtLoginLoading: false,
			onAccountsChange: () => undefined,
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
			accounts: [],
			preferences,
			launchAtLogin: false,
			launchAtLoginLoading: false,
			onAccountsChange: () => undefined,
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

describe("SettingsPanel weekly limits", () => {
	const accounts: LimitAccounts = [
		limitAccount("a1", "Max · main", localEpoch(2026, 9, 24, 15)),
		limitAccount("a2", "", localEpoch(2026, 9, 17, 15)),
		limitAccount("a3", "Codex", localEpoch(2026, 9, 23, 9)),
	];

	it("shows an empty hint and an add button when no accounts exist", () => {
		const html = renderSettingsPanel();

		expect(html).toContain("No accounts yet");
		expect(html).toContain("+ Add account");
		expect(html).toContain(`(0/${MAX_LIMIT_ACCOUNTS})`);
		expect(html).not.toContain('type="datetime-local"');
	});

	it("renders one editable row per account with accessible names", () => {
		const html = renderSettingsPanel({ accounts });

		expect(html.match(/class="limit-settings-row"/g)).toHaveLength(3);
		expect(html).toContain('aria-label="Account 1 label"');
		expect(html).toContain('aria-label="Account 2 next reset"');
		expect(html).toContain('aria-label="Remove Account 3"');
		expect(html).toContain('type="datetime-local"');
		expect(html).toContain('step="60"');
		expect(html).toContain('placeholder="Account 2"');
		expect(html).toContain('maxLength="40"');
		expect(html).toContain(`(3/${MAX_LIMIT_ACCOUNTS})`);
		expect(html).toContain("does not read actual usage");
	});

	it("shows the normalized next reset for a stale anchor", () => {
		const html = renderSettingsPanel({ accounts });

		expect(html).toContain('value="2026-09-24T15:00"');
		expect(html).not.toContain('value="2026-09-17T15:00"');
	});

	it("adds a deterministic account after the existing ones", () => {
		const calls: LimitAccounts[] = [];
		const element = settingsPanelElement(accounts, (next) => {
			calls.push(next);
		});
		const addButton = collectByType<ButtonProps>(element, "button").find(
			(button) => button.className === "limit-settings-add",
		);

		addButton?.onClick?.();

		expect(addButton?.disabled).toBe(false);
		expect(calls).toEqual([
			[...accounts, newLimitAccount(accounts, settingsNow, () => "created-id")],
		]);
	});

	it("updates only the edited account label", () => {
		const calls: LimitAccounts[] = [];
		const element = settingsPanelElement(accounts, (next) => {
			calls.push(next);
		});
		const labelInput = collectByType<TextInputProps>(element, "input").find(
			(input) => input.id === "limit-account-2-label",
		);

		labelInput?.onChange?.({ currentTarget: { value: "Work" } });

		expect(calls).toEqual([
			[accounts[0], { ...accounts[1], label: "Work" }, accounts[2]],
		]);
	});

	it("stores a valid next reset as local epoch seconds and ignores invalid input", () => {
		const calls: LimitAccounts[] = [];
		const element = settingsPanelElement(accounts, (next) => {
			calls.push(next);
		});
		const nextResetInput = collectByType<TextInputProps>(element, "input").find(
			(input) => input.id === "limit-account-1-next-reset",
		);

		nextResetInput?.onChange?.({ currentTarget: { value: "" } });
		nextResetInput?.onChange?.({ currentTarget: { value: "abc" } });
		nextResetInput?.onChange?.({
			currentTarget: { value: "2026-09-30T09:30" },
		});

		expect(calls).toEqual([
			[
				{ ...accounts[0], nextResetAt: localEpoch(2026, 9, 30, 9, 30) },
				accounts[1],
				accounts[2],
			],
		]);
	});

	it("removes the account behind the remove button", () => {
		const calls: LimitAccounts[] = [];
		const element = settingsPanelElement(accounts, (next) => {
			calls.push(next);
		});
		const removeButton = collectByType<ButtonProps>(element, "button").find(
			(button) => button["aria-label"] === "Remove Account 2",
		);

		removeButton?.onClick?.();

		expect(calls).toEqual([[accounts[0], accounts[2]]]);
	});

	it("disables adding once the maximum is reached", () => {
		const full = Array.from({ length: MAX_LIMIT_ACCOUNTS }, (_, index) =>
			limitAccount(
				`id-${index}`,
				`Account ${index + 1}`,
				localEpoch(2026, 9, 24, 15),
			),
		);
		const element = settingsPanelElement(full, () => undefined);
		const addButton = collectByType<ButtonProps>(element, "button").find(
			(button) => button.className === "limit-settings-add",
		);

		expect(addButton?.disabled).toBe(true);
		expect(renderSettingsPanel({ accounts: full })).toContain(
			`(${MAX_LIMIT_ACCOUNTS}/${MAX_LIMIT_ACCOUNTS})`,
		);
	});

	it("passes the account props through SettingsView", () => {
		const source = readFileSync("src/ui/SettingsView.tsx", "utf8");

		expect(source).toContain("accounts={accounts}");
		expect(source).toContain("onAccountsChange={onAccountsChange}");
	});

	it("lays out account rows in settings.css with a narrow-width fallback", () => {
		const css = readFileSync("src/styles/settings.css", "utf8");

		expect(css).toMatch(
			/\.limit-settings-row\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\) auto 32px/s,
		);
		expect(css).toMatch(
			/\.limit-settings-row input\[type="text"\],\s*\.limit-settings-row input\[type="datetime-local"\]\s*\{[^}]*color-scheme:\s*dark/s,
		);
		expect(css).toMatch(
			/\.limit-settings-list\s*\{[^}]*container-type:\s*inline-size[^}]*font-size:\s*var\(--fs-ui\)/s,
		);
		expect(css).toMatch(
			/@container \(max-width: 30em\)\s*\{[\s\S]*?\.limit-settings-row\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\) 32px/s,
		);
		expect(css).toContain(".limit-settings-empty");
		expect(css).toContain(".limit-settings-add");
		expect(css).toContain(".limit-settings-remove");
	});
});
