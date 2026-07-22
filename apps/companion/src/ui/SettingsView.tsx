import type { CompanionPreferences } from "../application/preferences";
import { SettingsPanel } from "./SettingsPanel";

type Props = {
	readonly preferences: CompanionPreferences;
	readonly launchAtLogin: boolean;
	readonly launchAtLoginLoading: boolean;
	readonly onLaunchAtLoginChange: (enabled: boolean) => void;
	readonly onPreferencesChange: (preferences: CompanionPreferences) => void;
};

export function SettingsView({
	preferences,
	launchAtLogin,
	launchAtLoginLoading,
	onLaunchAtLoginChange,
	onPreferencesChange,
}: Props) {
	return (
		<section className="settings-view view-panel" aria-label="Settings View">
			<SettingsPanel
				preferences={preferences}
				launchAtLogin={launchAtLogin}
				launchAtLoginLoading={launchAtLoginLoading}
				onLaunchAtLoginChange={onLaunchAtLoginChange}
				onPreferencesChange={onPreferencesChange}
			/>
		</section>
	);
}
