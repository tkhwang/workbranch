import type { ClaudeLimitRelayStatus } from "../infrastructure/tauriClient";
import { SettingsRow } from "./SettingsLayout";

export type ClaudeLimitRelayProps = {
	readonly status: ClaudeLimitRelayStatus | undefined;
	readonly loading: boolean;
	readonly onChange: (enabled: boolean) => void;
};

function hint({ status, loading }: ClaudeLimitRelayProps): string {
	if (loading && status === undefined)
		return "Checking Claude Code's status line";
	if (status === undefined) return "Claude Code's settings could not be read";
	if (!status.enabled)
		return "Off: limits come from Claude Code's /usage cache, which can be hours old. Turning this on points statusLine in Claude's settings.json at a relay that saves the 5h and weekly limits, then runs your current status line unchanged.";
	return status.previousCommand === null
		? "On: limits update while a Claude Code session is open. No status line text is shown; turning this off removes the relay."
		: `On: limits update while a Claude Code session is open. Your status line still runs: ${status.previousCommand}`;
}

export function ClaudeLimitRelaySettings(props: ClaudeLimitRelayProps) {
	const { status, loading, onChange } = props;
	return (
		<SettingsRow
			description={hint(props)}
			htmlFor="claude-limit-relay"
			title="Live Claude Limits"
		>
			<input
				aria-checked={status?.enabled ?? false}
				checked={status?.enabled ?? false}
				className="settings-switch"
				disabled={loading || status === undefined}
				id="claude-limit-relay"
				onChange={(event) => onChange(event.currentTarget.checked)}
				role="switch"
				type="checkbox"
			/>
		</SettingsRow>
	);
}
