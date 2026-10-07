import type { ReactNode } from "react";
import type { CompanionPreferences } from "../application/preferences";
import type { ClaudeLimitRelayProps } from "./ClaudeLimitRelaySettings";
import { SettingsPanel } from "./SettingsPanel";

type Props = {
	readonly claudeLimitRelay: ClaudeLimitRelayProps;
	readonly connections?: ReactNode;
	readonly preferences: CompanionPreferences;
	readonly launchAtLogin: boolean;
	readonly launchAtLoginLoading: boolean;
	readonly onLaunchAtLoginChange: (enabled: boolean) => void;
	readonly onPreferencesChange: (preferences: CompanionPreferences) => void;
};

export function SettingsView({
	claudeLimitRelay,
	connections,
	preferences,
	launchAtLogin,
	launchAtLoginLoading,
	onLaunchAtLoginChange,
	onPreferencesChange,
}: Props) {
	return (
		<section className="settings-view view-panel" aria-label="Settings View">
			{connections}
			<SettingsPanel
				claudeLimitRelay={claudeLimitRelay}
				preferences={preferences}
				launchAtLogin={launchAtLogin}
				launchAtLoginLoading={launchAtLoginLoading}
				onLaunchAtLoginChange={onLaunchAtLoginChange}
				onPreferencesChange={onPreferencesChange}
			/>
		</section>
	);
}
