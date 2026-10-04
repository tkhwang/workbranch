import type { ReactNode } from "react";
import type { LimitAccounts } from "../application/limits";
import type { CompanionPreferences } from "../application/preferences";
import { SettingsPanel } from "./SettingsPanel";

type Props = {
	readonly connections?: ReactNode;
	readonly accounts: LimitAccounts;
	readonly preferences: CompanionPreferences;
	readonly launchAtLogin: boolean;
	readonly launchAtLoginLoading: boolean;
	readonly onAccountsChange: (accounts: LimitAccounts) => void;
	readonly onLaunchAtLoginChange: (enabled: boolean) => void;
	readonly onPreferencesChange: (preferences: CompanionPreferences) => void;
};

export function SettingsView({
	connections,
	accounts,
	preferences,
	launchAtLogin,
	launchAtLoginLoading,
	onAccountsChange,
	onLaunchAtLoginChange,
	onPreferencesChange,
}: Props) {
	return (
		<section className="settings-view view-panel" aria-label="Settings View">
			{connections}
			<SettingsPanel
				accounts={accounts}
				preferences={preferences}
				launchAtLogin={launchAtLogin}
				launchAtLoginLoading={launchAtLoginLoading}
				onAccountsChange={onAccountsChange}
				onLaunchAtLoginChange={onLaunchAtLoginChange}
				onPreferencesChange={onPreferencesChange}
			/>
		</section>
	);
}
