import type { ReactNode } from "react";
import type { CompanionPreferences } from "../application/preferences";
import type { ClaudeLimitRelayProps } from "./ClaudeLimitRelaySettings";
import type { IdeWindowAccessProps } from "./IdeWindowSettings";
import {
	type SettingsAttention,
	type SettingsCategory,
	SettingsNav,
} from "./SettingsNav";
import { SettingsPanel } from "./SettingsPanel";

type Props = {
	readonly category: SettingsCategory;
	readonly onCategoryChange: (category: SettingsCategory) => void;
	/** Tabs that hold something to act on get a dot. */
	readonly attention?: SettingsAttention;
	readonly status?: ReactNode;
	readonly connections?: ReactNode;
	readonly claudeLimitRelay: ClaudeLimitRelayProps;
	readonly ideWindowAccess: IdeWindowAccessProps;
	readonly preferences: CompanionPreferences;
	readonly launchAtLogin: boolean;
	readonly launchAtLoginLoading: boolean;
	readonly onLaunchAtLoginChange: (enabled: boolean) => void;
	readonly onPreferencesChange: (preferences: CompanionPreferences) => void;
	readonly onScreensaverPreview: () => void;
};

export function SettingsView({
	category,
	onCategoryChange,
	attention = {},
	status,
	connections,
	claudeLimitRelay,
	ideWindowAccess,
	preferences,
	launchAtLogin,
	launchAtLoginLoading,
	onLaunchAtLoginChange,
	onPreferencesChange,
	onScreensaverPreview,
}: Props) {
	return (
		<section className="settings-view view-panel" aria-label="Settings View">
			<SettingsNav
				attention={attention}
				current={category}
				onChange={onCategoryChange}
			/>
			{category === "connections" ? (
				connections
			) : (
				<SettingsPanel
					category={category}
					claudeLimitRelay={claudeLimitRelay}
					ideWindowAccess={ideWindowAccess}
					launchAtLogin={launchAtLogin}
					launchAtLoginLoading={launchAtLoginLoading}
					onLaunchAtLoginChange={onLaunchAtLoginChange}
					onPreferencesChange={onPreferencesChange}
					onScreensaverPreview={onScreensaverPreview}
					preferences={preferences}
					status={status}
				/>
			)}
		</section>
	);
}
