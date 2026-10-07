import type { ClaudeLimitRelayStatus } from "../infrastructure/tauriClient";

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
		<>
			<div className="settings-row">
				<label htmlFor="claude-limit-relay">Live Claude Limits</label>
				<input
					checked={status?.enabled ?? false}
					disabled={loading || status === undefined}
					id="claude-limit-relay"
					onChange={(event) => onChange(event.currentTarget.checked)}
					type="checkbox"
				/>
			</div>
			<p className="settings-hint">{hint(props)}</p>
		</>
	);
}
