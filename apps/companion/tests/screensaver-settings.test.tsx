import { Children, isValidElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

const tauri = vi.hoisted(() => ({ invoke: vi.fn(), listen: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: tauri.invoke }));
vi.mock("@tauri-apps/api/event", () => ({ listen: tauri.listen }));

import { DEFAULT_IDE_WINDOW } from "../src/application/ideWindow";
import { DEFAULT_MENU_BAR } from "../src/application/menuBar";
import type { CompanionPreferences } from "../src/application/preferences";
import {
	DEFAULT_SCREENSAVER,
	type ScreensaverConfig,
} from "../src/application/screensaver";
import {
	previewScreensaver,
	readScreensaverStatus,
	refreshScreensaver,
} from "../src/infrastructure/tauriClient";
import { ScreensaverSettings } from "../src/ui/ScreensaverSettings";
import { SettingsPanel } from "../src/ui/SettingsPanel";

type FieldProps = {
	readonly id?: string;
	readonly checked?: boolean;
	readonly disabled?: boolean;
	readonly value?: string | number;
	readonly onChange?: (event: {
		readonly currentTarget: {
			readonly checked: boolean;
			readonly value: string;
		};
	}) => void;
	readonly children?: ReactNode;
};

type PickerProps = {
	readonly value: ScreensaverConfig;
	readonly onChange: (config: ScreensaverConfig) => void;
	readonly onPreview: () => void;
	readonly children?: ReactNode;
};

function findField(node: ReactNode, id: string): FieldProps | undefined {
	let found: FieldProps | undefined;
	const visit = (child: ReactNode): void => {
		if (!isValidElement<FieldProps>(child)) return;
		if (child.props.id === id) found = child.props;
		Children.forEach(child.props.children, visit);
	};
	visit(node);
	return found;
}

function findPicker(node: ReactNode): PickerProps | undefined {
	let found: PickerProps | undefined;
	const visit = (child: ReactNode): void => {
		if (!isValidElement<PickerProps>(child)) return;
		if (child.type === ScreensaverSettings) found = child.props;
		Children.forEach(child.props.children, visit);
	};
	visit(node);
	return found;
}

const preferences: CompanionPreferences = {
	font: "system-mono",
	fontSize: "medium",
	theme: "claude",
	menuBar: DEFAULT_MENU_BAR,
	screensaver: DEFAULT_SCREENSAVER,
	ideWindow: DEFAULT_IDE_WINDOW,
};

const ideWindowAccess = {
	granted: true,
	loading: false,
	onRequest: () => undefined,
	onOpenSettings: () => undefined,
};

describe("ScreensaverSettings", () => {
	it("starts switched off and leaves the Mac to macOS", () => {
		const html = renderToStaticMarkup(
			<ScreensaverSettings
				value={DEFAULT_SCREENSAVER}
				onChange={() => undefined}
				onPreview={() => undefined}
			/>,
		);
		expect(html).toMatch(/id="screensaver-enabled"(?![^>]*checked)/);
		expect(html).toContain("macOS handles sleep");
	});

	it("has no idle-minutes choice: the macOS screen saver decides when", () => {
		const html = renderToStaticMarkup(
			<ScreensaverSettings
				value={{ enabled: true, showMessages: false }}
				onChange={() => undefined}
				onPreview={() => undefined}
			/>,
		);
		expect(html).not.toContain("<select");
		expect(html).not.toContain('id="screensaver-idle"');
		expect(html).toContain("macOS screen saver starts or the screen locks");
		expect(html).toContain("over the lock screen");
	});

	it("turns the feature on", () => {
		const changes: ScreensaverConfig[] = [];
		const element = ScreensaverSettings({
			value: DEFAULT_SCREENSAVER,
			onChange: (config) => changes.push(config),
			onPreview: () => undefined,
		});
		findField(element, "screensaver-enabled")?.onChange?.({
			currentTarget: { checked: true, value: "on" },
		});
		expect(changes).toEqual([{ enabled: true, showMessages: false }]);
	});

	it("keeps messages off the dashboard until asked", () => {
		const html = renderToStaticMarkup(
			<ScreensaverSettings
				value={DEFAULT_SCREENSAVER}
				onChange={() => undefined}
				onPreview={() => undefined}
			/>,
		);
		expect(html).toMatch(/id="screensaver-show-messages"(?![^>]*checked)/);
		expect(html).toContain("anyone at the desk");
	});

	it("shows recent messages on the dashboard", () => {
		const changes: ScreensaverConfig[] = [];
		const element = ScreensaverSettings({
			value: DEFAULT_SCREENSAVER,
			onChange: (config) => changes.push(config),
			onPreview: () => undefined,
		});
		findField(element, "screensaver-show-messages")?.onChange?.({
			currentTarget: { checked: true, value: "on" },
		});
		expect(changes).toEqual([{ enabled: false, showMessages: true }]);
	});
});

describe("SettingsPanel screen saver section", () => {
	it("renders a Screen Saver panel", () => {
		const html = renderToStaticMarkup(
			<SettingsPanel
				category="screen-saver"
				claudeLimitRelay={{
					status: { enabled: false, previousCommand: null },
					loading: false,
					onChange: () => undefined,
				}}
				ideWindowAccess={ideWindowAccess}
				preferences={preferences}
				launchAtLogin={false}
				launchAtLoginLoading={false}
				onLaunchAtLoginChange={() => undefined}
				onPreferencesChange={() => undefined}
				onScreensaverPreview={() => undefined}
			/>,
		);
		expect(html).toContain("04 · Screen Saver");
		expect(html).toContain('aria-label="Screen Saver"');
		expect(html).toContain('id="screensaver-enabled"');
	});

	it("delegates the edited screensaver config", () => {
		const calls: CompanionPreferences[] = [];
		const element = SettingsPanel({
			category: "screen-saver",
			claudeLimitRelay: {
				status: { enabled: false, previousCommand: null },
				loading: false,
				onChange: () => undefined,
			},
			ideWindowAccess,
			preferences,
			launchAtLogin: false,
			launchAtLoginLoading: false,
			onLaunchAtLoginChange: () => undefined,
			onPreferencesChange: (next) => calls.push(next),
			onScreensaverPreview: () => undefined,
		});
		const edited = { enabled: true };
		findPicker(element)?.onChange(edited);
		expect(calls).toEqual([{ ...preferences, screensaver: edited }]);
	});
});

describe("refreshScreensaver", () => {
	beforeEach(() => tauri.invoke.mockReset());

	it("asks the Rust side to re-read the preference", async () => {
		tauri.invoke.mockResolvedValue(undefined);
		await refreshScreensaver();
		expect(tauri.invoke).toHaveBeenCalledWith("screensaver_refresh");
	});
});

describe("readScreensaverStatus", () => {
	beforeEach(() => tauri.invoke.mockReset());

	it("reports whether input can lock the Mac", async () => {
		tauri.invoke.mockResolvedValue({ lockAvailable: false });
		await expect(readScreensaverStatus()).resolves.toEqual({
			lockAvailable: false,
		});
		expect(tauri.invoke).toHaveBeenCalledWith("screensaver_status");
	});

	it("rejects a status outside the contract", async () => {
		tauri.invoke.mockResolvedValue({ lockAvailable: "yes" });
		await expect(readScreensaverStatus()).rejects.toThrow(/screensaver status/);
	});
});

type ButtonProps = {
	readonly type?: string;
	readonly onClick?: () => void;
	readonly children?: ReactNode;
	readonly "aria-label"?: string;
};

function findPreviewButton(node: ReactNode): ButtonProps | undefined {
	let found: ButtonProps | undefined;
	const visit = (child: ReactNode): void => {
		if (!isValidElement<ButtonProps>(child)) return;
		if (
			child.type === "button" &&
			child.props["aria-label"] === "Preview the dashboard"
		)
			found = child.props;
		Children.forEach(child.props.children, visit);
	};
	visit(node);
	return found;
}

describe("Screen saver preview", () => {
	it("offers a preview button even while the feature is off", () => {
		const html = renderToStaticMarkup(
			<ScreensaverSettings
				value={DEFAULT_SCREENSAVER}
				onChange={() => undefined}
				onPreview={() => undefined}
			/>,
		);
		expect(html).toMatch(
			/<button[^>]*aria-label="Preview the dashboard"(?![^>]*disabled)[^>]*type="button"/,
		);
	});

	it("asks for a preview when the button is pressed", () => {
		let previews = 0;
		const element = ScreensaverSettings({
			value: DEFAULT_SCREENSAVER,
			onChange: () => undefined,
			onPreview: () => {
				previews += 1;
			},
		});
		findPreviewButton(element)?.onClick?.();
		expect(previews).toBe(1);
	});

	it("passes the preview request up from the settings panel", () => {
		let previews = 0;
		const element = SettingsPanel({
			category: "screen-saver",
			claudeLimitRelay: {
				status: { enabled: false, previousCommand: null },
				loading: false,
				onChange: () => undefined,
			},
			ideWindowAccess,
			preferences,
			launchAtLogin: false,
			launchAtLoginLoading: false,
			onLaunchAtLoginChange: () => undefined,
			onPreferencesChange: () => undefined,
			onScreensaverPreview: () => {
				previews += 1;
			},
		});
		findPicker(element)?.onPreview();
		expect(previews).toBe(1);
	});

	it("invokes the Rust preview command", async () => {
		tauri.invoke.mockReset();
		tauri.invoke.mockResolvedValue(undefined);
		await previewScreensaver();
		expect(tauri.invoke).toHaveBeenCalledWith("screensaver_preview");
	});
});
