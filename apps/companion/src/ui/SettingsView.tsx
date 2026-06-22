import type {
	CompanionPreferences,
	CompanionResolvedThemeMode,
} from "../application/preferences";
import { SettingsPanel } from "./SettingsPanel";

type Props = {
	readonly preferences: CompanionPreferences;
	readonly systemThemeMode: CompanionResolvedThemeMode;
	readonly launchAtLogin: boolean;
	readonly launchAtLoginLoading: boolean;
	readonly onLaunchAtLoginChange: (enabled: boolean) => void;
	readonly onPreferencesChange: (preferences: CompanionPreferences) => void;
};

export function SettingsView({
	preferences,
	systemThemeMode,
	launchAtLogin,
	launchAtLoginLoading,
	onLaunchAtLoginChange,
	onPreferencesChange,
}: Props) {
	return (
		<section className="settings-view view-panel" aria-label="Settings View">
			<SettingsPanel
				preferences={preferences}
				systemThemeMode={systemThemeMode}
				launchAtLogin={launchAtLogin}
				launchAtLoginLoading={launchAtLoginLoading}
				onLaunchAtLoginChange={onLaunchAtLoginChange}
				onPreferencesChange={onPreferencesChange}
			/>
		</section>
	);
}
