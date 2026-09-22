import type { ReactNode } from "react";
import {
	LIMIT_LABEL_MAX_LENGTH,
	type LimitAccount,
	type LimitAccounts,
	MAX_LIMIT_ACCOUNTS,
	newLimitAccount,
} from "../application/limits";
import type { CompanionPreferences } from "../application/preferences";
import {
	COMPANION_FONT_OPTIONS,
	COMPANION_FONT_SIZE_OPTIONS,
	isCompanionFont,
	isCompanionFontSize,
} from "../application/preferences";
import {
	formatDateTimeLocal,
	parseDateTimeLocal,
	resolveNextReset,
} from "../domain/limits";
import { AgentThemePicker } from "./AgentThemePicker";
import { TerminalPanel } from "./TerminalPanel";

type Props = {
	readonly accounts: LimitAccounts;
	readonly preferences: CompanionPreferences;
	readonly launchAtLogin: boolean;
	readonly launchAtLoginLoading: boolean;
	readonly now?: () => Date;
	readonly createId?: () => string;
	readonly onAccountsChange: (accounts: LimitAccounts) => void;
	readonly onLaunchAtLoginChange: (enabled: boolean) => void;
	readonly onPreferencesChange: (preferences: CompanionPreferences) => void;
};

function defaultNow(): Date {
	return new Date();
}

function defaultCreateId(): string {
	return crypto.randomUUID();
}

function replaceAccount(
	accounts: LimitAccounts,
	index: number,
	next: LimitAccount,
): LimitAccounts {
	return accounts.map((account, candidate) =>
		candidate === index ? next : account,
	);
}

// Rendered as a plain function so the rows stay inline in the panel tree.
function limitAccountRows(
	accounts: LimitAccounts,
	nowSeconds: number,
	onAccountsChange: (accounts: LimitAccounts) => void,
): ReactNode {
	if (accounts.length === 0) {
		return <p className="limit-settings-empty">No accounts yet</p>;
	}
	return (
		<ul className="limit-settings-list">
			{accounts.map((account, index) => {
				const number = index + 1;
				const nextReset = resolveNextReset(account.nextResetAt, nowSeconds);
				return (
					<li className="limit-settings-row" key={account.id}>
						<input
							aria-label={`Account ${number} label`}
							className="limit-settings-name"
							id={`limit-account-${number}-label`}
							maxLength={LIMIT_LABEL_MAX_LENGTH}
							onChange={(event) => {
								onAccountsChange(
									replaceAccount(accounts, index, {
										...account,
										label: event.currentTarget.value.slice(
											0,
											LIMIT_LABEL_MAX_LENGTH,
										),
									}),
								);
							}}
							placeholder={`Account ${number}`}
							type="text"
							value={account.label}
						/>
						<input
							aria-label={`Account ${number} next reset`}
							id={`limit-account-${number}-next-reset`}
							onChange={(event) => {
								const nextResetAt = parseDateTimeLocal(
									event.currentTarget.value,
								);
								if (nextResetAt === undefined) return;
								onAccountsChange(
									replaceAccount(accounts, index, { ...account, nextResetAt }),
								);
							}}
							step={60}
							type="datetime-local"
							value={formatDateTimeLocal(nextReset)}
						/>
						<button
							aria-label={`Remove Account ${number}`}
							className="limit-settings-remove"
							onClick={() => {
								onAccountsChange(
									accounts.filter((candidate) => candidate.id !== account.id),
								);
							}}
							type="button"
						>
							×
						</button>
					</li>
				);
			})}
		</ul>
	);
}

export function SettingsPanel({
	accounts,
	preferences,
	launchAtLogin,
	launchAtLoginLoading,
	now = defaultNow,
	createId = defaultCreateId,
	onAccountsChange,
	onLaunchAtLoginChange,
	onPreferencesChange,
}: Props) {
	const fontOption = COMPANION_FONT_OPTIONS.find(
		(candidate) => candidate.value === preferences.font,
	);
	const fontFamily = fontOption?.cssFamily ?? preferences.font;
	const fontName = fontOption?.label ?? preferences.font;
	const fontSizeOption = COMPANION_FONT_SIZE_OPTIONS.find(
		(candidate) => candidate.value === preferences.fontSize,
	);
	const fontSizeName = fontSizeOption?.label ?? preferences.fontSize;
	const nowSeconds = Math.floor(now().getTime() / 1000);

	return (
		<section className="settings-panel" aria-label="Settings">
			<div className="settings-panel-header">
				<div>
					<h2>Settings</h2>
					<p>Companion preferences</p>
				</div>
			</div>
			<TerminalPanel anatomy="claude" label="Startup" theme={preferences.theme}>
				<div className="settings-row">
					<label htmlFor="launch-at-login">Open at Login</label>
					<input
						checked={launchAtLogin}
						disabled={launchAtLoginLoading}
						id="launch-at-login"
						onChange={(event) =>
							onLaunchAtLoginChange(event.currentTarget.checked)
						}
						type="checkbox"
					/>
				</div>
				<p className="settings-hint">
					{launchAtLoginLoading
						? "Checking login item state"
						: launchAtLogin
							? "Opens automatically when you sign in"
							: "Opens only when opened manually"}
				</p>
			</TerminalPanel>
			<TerminalPanel anatomy="claude" label="Font" theme={preferences.theme}>
				<div className="settings-row settings-row-select">
					<label htmlFor="companion-font">Font</label>
					<select
						id="companion-font"
						onChange={(event) => {
							const nextFont = event.currentTarget.value;
							if (isCompanionFont(nextFont)) {
								onPreferencesChange({ ...preferences, font: nextFont });
							}
						}}
						value={preferences.font}
					>
						{COMPANION_FONT_OPTIONS.map((option) => (
							<option key={option.value} value={option.value}>
								{option.label}
							</option>
						))}
					</select>
				</div>
				<div className="font-preview" style={{ fontFamily }}>
					<span className="font-preview-label">Preview · {fontName}</span>
					<code>workbranch feat/update-0619</code>
					<span>1234567890 · RUN 1 · 21/21</span>
				</div>
				<p className="settings-hint">Current font: {fontName}</p>
			</TerminalPanel>
			<TerminalPanel
				anatomy="claude"
				label="Text Size"
				theme={preferences.theme}
			>
				<div className="settings-row settings-row-select">
					<label htmlFor="companion-font-size">Text Size</label>
					<select
						id="companion-font-size"
						onChange={(event) => {
							const nextFontSize = event.currentTarget.value;
							if (isCompanionFontSize(nextFontSize)) {
								onPreferencesChange({
									...preferences,
									fontSize: nextFontSize,
								});
							}
						}}
						value={preferences.fontSize}
					>
						{COMPANION_FONT_SIZE_OPTIONS.map((option) => (
							<option key={option.value} value={option.value}>
								{option.label}
							</option>
						))}
					</select>
				</div>
				<div className="font-preview">
					<span className="font-preview-label">Preview · {fontSizeName}</span>
					<code>workbranch feat/update-0619</code>
					<span className="font-preview-meta">
						ci: build signed macOS DMGs · 11d
					</span>
				</div>
				<p className="settings-hint">
					Scales every text size in Main, Activity, and Settings.
				</p>
			</TerminalPanel>
			<TerminalPanel anatomy="claude" label="Theme" theme={preferences.theme}>
				<AgentThemePicker
					value={preferences.theme}
					onChange={(theme) => onPreferencesChange({ ...preferences, theme })}
				/>
				<p className="settings-hint">
					Applies immediately across Main, Activity, and Settings.
				</p>
			</TerminalPanel>
			<TerminalPanel
				anatomy="claude"
				label="Weekly Limits"
				theme={preferences.theme}
			>
				{limitAccountRows(accounts, nowSeconds, onAccountsChange)}
				<button
					className="limit-settings-add"
					disabled={accounts.length >= MAX_LIMIT_ACCOUNTS}
					onClick={() => {
						onAccountsChange([
							...accounts,
							newLimitAccount(accounts, now(), createId),
						]);
					}}
					type="button"
				>
					+ Add account
				</button>
				<p className="settings-hint">
					Enter the next reset shown in /usage. After it passes, the next reset
					moves forward 7 days. Main shows each account's window on a shared
					two-week axis — it does not read actual usage. ({accounts.length}/
					{MAX_LIMIT_ACCOUNTS})
				</p>
			</TerminalPanel>
		</section>
	);
}
