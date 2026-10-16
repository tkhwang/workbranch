import type { ConnectionState } from "../application/connections";
import {
	companionRestartPending,
	type PackageVersion,
	type UpdateState,
	type UpdateTarget,
	updateActionLabel,
	updateTargets,
} from "../application/updates";
import {
	AGENT_NAMES,
	agentStateLabel,
	cliStateLabel,
} from "./ConnectionsPanel";
import { ProgressButton } from "./ProgressButton";
import {
	SettingsBadge,
	SettingsGroup,
	SettingsNote,
	SettingsRow,
	type SettingsTone,
} from "./SettingsLayout";

type Props = {
	readonly updates: UpdateState;
	readonly connections: ConnectionState;
	readonly onCheckUpdates: () => void;
	readonly onApplyUpdates: () => void;
	readonly onOpenConnections: () => void;
};

const TARGET_NAMES: Record<UpdateTarget, string> = {
	cli: "CLI",
	companion: "Companion",
};

function versionBadge(version: PackageVersion): string {
	if (version.latest === null) return "확인 불가";
	if (version.installed === null) return "Homebrew 미설치";
	return version.outdated ? "업데이트 있음" : "최신";
}

function versionTone(version: PackageVersion): SettingsTone {
	if (version.latest === null || version.installed === null) return "neutral";
	return version.outdated ? "notice" : "success";
}

function versionLine(version: PackageVersion): string {
	const installed = version.installed ?? "없음";
	const latest = version.latest ?? "알 수 없음";
	return version.outdated
		? `설치 ${installed} → 최신 ${latest}`
		: `설치 ${installed} · 최신 ${latest}`;
}

function connectionSummary({ status, loading }: ConnectionState): string {
	if (status === null)
		return loading
			? "설치 상태를 확인하고 있습니다…"
			: "설치 상태를 읽을 수 없습니다.";
	const agents = status.agents.map(
		(agent) => `${AGENT_NAMES[agent.provider]} ${agentStateLabel(agent.state)}`,
	);
	return [`CLI ${cliStateLabel(status.cli)}`, ...agents].join(" · ");
}

/**
 * What needs a decision comes first on General: the check's outcome (with
 * the one button that applies updates), then CLI and Companion versions in
 * the order the update runs, the update log, and whether agents are ready.
 * The check stays click-only because it runs `brew update`.
 */
export function StatusSettings({
	updates,
	connections,
	onCheckUpdates,
	onApplyUpdates,
	onOpenConnections,
}: Props) {
	const { status, checking, updating, restarting } = updates;
	const busy = checking || updating || restarting;
	const targets = updateTargets(status);
	return (
		<SettingsGroup
			action={
				<ProgressButton
					pending={checking}
					pendingLabel="확인 중…"
					disabled={busy}
					onClick={onCheckUpdates}
				>
					{status === null ? "업데이트 확인" : "다시 확인"}
				</ProgressButton>
			}
			label="Status"
		>
			{targets.length > 0 ? (
				<SettingsNote
					action={
						<ProgressButton
							pending={updating || restarting}
							pendingLabel={restarting ? "재시작 중…" : "업데이트 중…"}
							disabled={busy}
							onClick={onApplyUpdates}
						>
							{updateActionLabel(targets)}
						</ProgressButton>
					}
					icon="download"
					tone="notice"
				>
					업데이트 있음 ·{" "}
					{targets.map((target) => TARGET_NAMES[target]).join(", ")}
				</SettingsNote>
			) : null}
			{status?.brewPath && targets.length === 0 && !checking ? (
				<SettingsNote icon="check" role="status" tone="success">
					업데이트할 항목이 없습니다.
				</SettingsNote>
			) : null}
			{updates.error ? (
				<SettingsNote icon="alert" role="alert" tone="danger">
					{updates.error}
				</SettingsNote>
			) : null}
			{updates.notice ? (
				<SettingsNote icon="check" role="status" tone="success">
					{updates.notice}
				</SettingsNote>
			) : null}
			{updating ? (
				<SettingsNote role="status">
					Homebrew 업데이트 중… 완료될 때까지 기다려 주세요.
				</SettingsNote>
			) : null}
			{status?.fetchError ? (
				<SettingsNote icon="alert" tone="notice">
					Homebrew 정보를 갱신하지 못해 최신 버전이 오래됐을 수 있습니다:{" "}
					{status.fetchError}
				</SettingsNote>
			) : null}
			{status === null ? (
				<SettingsNote icon="info" role={checking ? "status" : undefined}>
					{checking
						? "최신 버전을 확인하고 있습니다…"
						: "Homebrew로 설치한 CLI와 Companion의 최신 버전을 확인합니다."}
				</SettingsNote>
			) : status.brewPath === null ? (
				<SettingsNote icon="info">
					Homebrew를 찾지 못했습니다. 실행 중인 Companion{" "}
					{status.runningVersion}
				</SettingsNote>
			) : (
				<>
					<SettingsRow
						badge={
							<SettingsBadge tone={versionTone(status.cli)}>
								{versionBadge(status.cli)}
							</SettingsBadge>
						}
						description={
							<>
								<span>{versionLine(status.cli)}</span>
								{status.cli.installed === null && status.cli.latest !== null ? (
									<span>Connections에서 CLI를 설치하세요.</span>
								) : null}
							</>
						}
						title="Workbranch CLI"
					/>
					<SettingsRow
						badge={
							<SettingsBadge tone={versionTone(status.companion)}>
								{versionBadge(status.companion)}
							</SettingsBadge>
						}
						description={
							<>
								<span>
									실행 중 {status.runningVersion} ·{" "}
									{versionLine(status.companion)}
								</span>
								{!status.selfUpdateSupported ? (
									<span>
										개발 빌드에서는 Companion을 업데이트하지 않습니다.
									</span>
								) : companionRestartPending(status) ? (
									<span>
										새 버전이 설치되어 있습니다. Companion을 다시 시작하면
										적용됩니다.
									</span>
								) : null}
							</>
						}
						title="Workbranch Companion"
					/>
				</>
			)}
			{updates.logs ? (
				<details className="settings-details">
					<summary>상세 로그</summary>
					<pre>{updates.logs}</pre>
				</details>
			) : null}
			<SettingsRow
				description={connectionSummary(connections)}
				title="Agent 연결"
			>
				<button onClick={onOpenConnections} type="button">
					연결 관리
				</button>
			</SettingsRow>
		</SettingsGroup>
	);
}
