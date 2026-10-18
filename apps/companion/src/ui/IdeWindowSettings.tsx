import type { IdeWindowConfig } from "../application/ideWindow";
import { SettingsGroup, SettingsRow } from "./SettingsLayout";

/** The Accessibility permission, which macOS grants in System Settings. */
export type IdeWindowAccessProps = {
	/** `undefined` until the first read comes back. */
	readonly granted: boolean | undefined;
	readonly loading: boolean;
	/** Shows macOS's prompt, which also lists Companion in System Settings. */
	readonly onRequest: () => void;
	readonly onOpenSettings: () => void;
};

type Props = IdeWindowAccessProps & {
	readonly value: IdeWindowConfig;
	readonly onChange: (config: IdeWindowConfig) => void;
};

function hint({ value, granted, loading }: Props): string {
	if (!value.enabled)
		return "Off: Zed, VS Code, Cursor and Antigravity IDE open a new window where they choose, often on the display they used last.";
	if (granted === undefined)
		return loading
			? "Checking the Accessibility permission"
			: "The Accessibility permission could not be read";
	if (!granted)
		return "Waiting for the Accessibility permission. Until it is on, the IDE places its windows itself.";
	return "On: a window the IDE action opens moves to the middle of the screen Companion is on. Windows that were already open stay where they are.";
}

/**
 * Moving another app's window needs the Accessibility permission, so turning
 * the switch on asks macOS for it; the switch alone changes nothing until
 * the permission is granted.
 */
export function IdeWindowSettings(props: Props) {
	const { value, onChange, granted, onRequest, onOpenSettings } = props;
	return (
		<SettingsGroup label="IDE Windows">
			<SettingsRow
				description={hint(props)}
				htmlFor="ide-window-enabled"
				title="Open on Companion's screen"
			>
				<input
					aria-checked={value.enabled}
					checked={value.enabled}
					className="settings-switch"
					id="ide-window-enabled"
					onChange={(event) => {
						const enabled = event.currentTarget.checked;
						onChange({ ...value, enabled });
						if (enabled && granted !== true) onRequest();
					}}
					role="switch"
					type="checkbox"
				/>
			</SettingsRow>
			{value.enabled && granted === false ? (
				<SettingsRow
					description="Turn on WorkbranchCompanion under Privacy & Security › Accessibility, then open Companion again."
					title="Accessibility"
				>
					<button onClick={onOpenSettings} type="button">
						Open System Settings
					</button>
				</SettingsRow>
			) : null}
		</SettingsGroup>
	);
}
