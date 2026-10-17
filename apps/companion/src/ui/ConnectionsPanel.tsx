import { type ReactNode, useState } from "react";
import type {
	ConnectionState,
	Provider,
	SetupAction,
	SetupStatus,
} from "../application/connections";
import {
	cliSetupAction,
	receiptState,
	sameSetupAction,
	setupTarget,
} from "../application/connections";
import type { CompanionTheme } from "../application/preferences";
import type { AgentSession } from "../domain/model";
import { ProgressButton } from "./ProgressButton";
import {
	SettingsBadge,
	SettingsGroup,
	SettingsNote,
	SettingsPage,
	SettingsRow,
	type SettingsTone,
} from "./SettingsLayout";
import { formatRelativeTime } from "./TaskRow";
import { TerminalPanel } from "./TerminalPanel";

type Agent = SetupStatus["agents"][number];

export const AGENT_NAMES: Record<Provider, string> = {
	claude: "Claude Code",
	codex: "Codex",
	grok: "Grok Build",
};
const pendingLabels: Record<SetupAction["kind"], string> = {
	installCli: "CLI 설치 중…",
	updateCli: "CLI 업데이트 중…",
	repairCli: "설치 복구 중…",
	connectAgent: "연결 중…",
	disconnectAgent: "연결 해제 중…",
};

export function cliStateLabel(cli: SetupStatus["cli"]): string {
	if (cli.state === "ready") return "준비됨";
	return cli.state === "missing" ? "미설치" : "확인 필요";
}

export function agentStateLabel(state: Agent["state"]): string {
	switch (state) {
		case "notInstalled":
			return "Agent 미설치";
		case "disabled":
			return "비활성";
		case "trustRequired":
			return "신뢰 승인 필요";
		case "configured":
			return "설정됨";
		case "unknown":
			return "확인 필요";
		case "disconnected":
			return "미연결";
	}
}

function agentTone(state: Agent["state"]): SettingsTone {
	if (state === "configured") return "success";
	if (state === "trustRequired" || state === "unknown") return "notice";
	return "neutral";
}

function SetupOutcome({
	error,
	notice,
}: {
	readonly error: string | null;
	readonly notice: string | null;
}) {
	return (
		<>
			{error ? (
				<SettingsNote icon="alert" role="alert" tone="danger">
					{error}
				</SettingsNote>
			) : null}
			{notice ? (
				<SettingsNote icon="check" role="status" tone="success">
					{notice}
				</SettingsNote>
			) : null}
		</>
	);
}
type Props = {
	readonly theme: CompanionTheme;
	readonly state: ConnectionState;
	readonly sessions?: readonly AgentSession[];
	readonly onRefresh: () => void;
	readonly onAction: (action: SetupAction) => void;
	readonly onboarding?: boolean;
	readonly onDismiss?: () => void;
};
export function GrokTrustPrompt({
	source,
	disabled,
	onApprove,
	onCancel,
}: {
	readonly source: string;
	readonly disabled: boolean;
	readonly onApprove: () => void;
	readonly onCancel: () => void;
}) {
	return (
		<fieldset className="grok-trust-prompt" aria-label="Grok plugin 설치 승인">
			<strong>Grok plugin을 신뢰하고 설치할까요?</strong>
			<p>
				Plugin에 포함된 hook·MCP·skill이 이 컴퓨터에서 실행될 수 있습니다. 아래
				Workbranch plugin과 hook 실행을 신뢰할 때만 승인하세요.
			</p>
			<p>
				설치 대상: <code style={{ overflowWrap: "anywhere" }}>{source}</code>
			</p>
			{disabled ? (
				<p>설치 대상이 변경됐거나 작업 중입니다. 대상을 다시 확인하세요.</p>
			) : null}
			<div className="connection-actions">
				<button type="button" disabled={disabled} onClick={onApprove}>
					신뢰하고 설치
				</button>
				<button type="button" onClick={onCancel}>
					취소
				</button>
			</div>
		</fieldset>
	);
}

export function ConnectionsPanel({
	theme,
	state,
	sessions = [],
	onRefresh,
	onAction,
	onboarding = false,
	onDismiss,
}: Props) {
	const { status, busy, loading } = state;
	const [trustSource, setTrustSource] = useState<string | null>(null);
	const pending = (action: SetupAction) =>
		busy !== null && sameSetupAction(busy, action);
	// Results appear beside the button that ran them; check failures stay on top.
	const outcomeTarget = state.lastAction ? setupTarget(state.lastAction) : null;
	const outcome = (target: "cli" | Provider) =>
		outcomeTarget === target ? (
			<SetupOutcome error={state.error} notice={state.notice} />
		) : null;
	const ready = status?.cli.state === "ready";
	const lastSeen = (agent: Agent) =>
		Math.max(
			agent.lastObservedAt ?? 0,
			...sessions
				.filter((s) => s.provider === agent.provider)
				.map((s) => s.updatedAt),
		);
	const verified =
		status?.agents.some(
			(agent) =>
				agent.state === "configured" &&
				receiptState(
					lastSeen(agent),
					state.verificationAfter[agent.provider],
				) === "verified",
		) ?? false;
	const refresh = (
		<ProgressButton
			pending={loading}
			pendingLabel="확인 중…"
			disabled={busy !== null}
			onClick={onRefresh}
		>
			다시 확인
		</ProgressButton>
	);

	const agentRow = (agent: Agent): ReactNode => {
		const seen = lastSeen(agent);
		const configured = agent.state === "configured";
		const receipt = receiptState(seen, state.verificationAfter[agent.provider]);
		const disabled = !ready || !agent.executablePath || busy !== null;
		const missingTrustTarget =
			agent.provider === "grok" && !agent.installSource;
		const now = Math.floor(Date.now() / 1000);
		return (
			<SettingsRow
				badge={
					<SettingsBadge tone={agentTone(agent.state)}>
						{agentStateLabel(agent.state)}
					</SettingsBadge>
				}
				description={
					<>
						<span>{agent.message}</span>
						{configured ? (
							<span className="connection-observation">
								{receipt === "verified"
									? `수신 확인됨 · 마지막 관측 ${formatRelativeTime(seen, now)} 전`
									: receipt === "historical"
										? `이전 수신 기록 · ${formatRelativeTime(seen, now)} 전 · 새 이벤트 확인 대기`
										: "첫 이벤트 수신 대기 · 설치만으로 수집 완료를 뜻하지 않습니다."}
							</span>
						) : null}
					</>
				}
				extra={
					<>
						{outcome(agent.provider)}
						{missingTrustTarget ? (
							<p className="settings-hint">
								Grok 설치 대상을 확인하려면 CLI를 업데이트하고 다시 확인하세요.
							</p>
						) : null}
						{agent.provider === "grok" && trustSource !== null ? (
							<GrokTrustPrompt
								source={trustSource}
								disabled={disabled || agent.installSource !== trustSource}
								onCancel={() => setTrustSource(null)}
								onApprove={() => {
									if (disabled || agent.installSource !== trustSource) return;
									const approvedSource = trustSource;
									setTrustSource(null);
									onAction({
										kind: "connectAgent",
										provider: "grok",
										approvedSource,
									});
								}}
							/>
						) : null}
						{configured || agent.state === "trustRequired" ? (
							<p className="settings-hint">
								Agent의 /hooks에서 연결과 신뢰 상태를 확인하세요. 기존 session은
								다시 시작해야 할 수 있습니다.
							</p>
						) : null}
					</>
				}
				key={agent.provider}
				title={AGENT_NAMES[agent.provider]}
			>
				<ProgressButton
					pending={pending({ kind: "connectAgent", provider: agent.provider })}
					pendingLabel={pendingLabels.connectAgent}
					disabled={disabled || missingTrustTarget}
					onClick={() => {
						if (agent.provider === "grok" && agent.installSource) {
							setTrustSource(agent.installSource);
						} else onAction({ kind: "connectAgent", provider: agent.provider });
					}}
				>
					{configured || agent.state === "disabled" ? "다시 연결" : "연결"}
				</ProgressButton>
				{agent.state !== "notInstalled" && agent.state !== "disconnected" ? (
					<ProgressButton
						pending={pending({
							kind: "disconnectAgent",
							provider: agent.provider,
						})}
						pendingLabel={pendingLabels.disconnectAgent}
						disabled={disabled}
						onClick={() =>
							onAction({ kind: "disconnectAgent", provider: agent.provider })
						}
					>
						연결 해제
					</ProgressButton>
				) : null}
			</SettingsRow>
		);
	};

	const content = (
		<>
			{outcomeTarget === null ? (
				<SetupOutcome error={state.error} notice={state.notice} />
			) : null}
			{status ? (
				<>
					<SettingsGroup ariaLabel="Install CLI" label="1 · Workbranch CLI">
						<SettingsRow
							badge={
								<SettingsBadge tone={ready ? "success" : "notice"}>
									{cliStateLabel(status.cli)}
								</SettingsBadge>
							}
							description={status.cli.message}
							extra={
								<>
									{outcome("cli")}
									{!status.brewPath ? (
										<p className="settings-hint">
											Homebrew를 찾지 못했습니다. 설치 또는 실행 경로를
											확인하세요.
										</p>
									) : null}
								</>
							}
							title="Workbranch CLI"
						>
							<ProgressButton
								pending={pending({ kind: cliSetupAction(status) })}
								pendingLabel={pendingLabels[cliSetupAction(status)]}
								disabled={!status.brewPath || busy !== null}
								onClick={() => onAction({ kind: cliSetupAction(status) })}
							>
								{cliSetupAction(status) === "installCli"
									? "CLI 설치"
									: cliSetupAction(status) === "repairCli"
										? "설치 복구"
										: "CLI 업데이트"}
							</ProgressButton>
							{ready && status.formulaInstalled === true ? (
								<ProgressButton
									pending={pending({ kind: "repairCli" })}
									pendingLabel={pendingLabels.repairCli}
									disabled={!status.brewPath || busy !== null}
									onClick={() => onAction({ kind: "repairCli" })}
								>
									설치 복구
								</ProgressButton>
							) : null}
						</SettingsRow>
						<details className="settings-details">
							<summary>버전 및 사용 경로</summary>
							<dl>
								<dt>CLI</dt>
								<dd>{status.cli.version || "확인되지 않음"}</dd>
								<dt>경로</dt>
								<dd>{status.cli.path || "없음"}</dd>
								<dt>설치 관리</dt>
								<dd>
									{status.formulaInstalled === true
										? "Homebrew"
										: status.formulaInstalled === false
											? "Homebrew formula 미설치"
											: "확인되지 않음"}
								</dd>
								<dt>Homebrew</dt>
								<dd>{status.brewPath || "없음"}</dd>
							</dl>
						</details>
					</SettingsGroup>
					<SettingsGroup ariaLabel="Connect AI Agent" label="2 · AI Agent 연결">
						{!ready ? (
							<SettingsNote icon="info">
								CLI 준비가 끝나면 agent를 연결할 수 있습니다.
							</SettingsNote>
						) : null}
						{status.agents.map(agentRow)}
					</SettingsGroup>
				</>
			) : loading ? (
				<p className="settings-hint" role="status">
					설치 상태를 확인하고 있습니다…
				</p>
			) : (
				<p className="settings-hint">
					설치 상태를 읽을 수 없습니다. 다시 확인하세요.
				</p>
			)}
			{busy ? (
				<p className="settings-hint" role="status">
					{busy.kind.endsWith("Agent")
						? "Agent 연결 작업 중…"
						: "Homebrew 작업 중…"}{" "}
					완료될 때까지 기다려 주세요.
				</p>
			) : null}
			{state.logs ? (
				<details className="settings-details connection-logs">
					<summary>상세 로그</summary>
					<pre>{state.logs}</pre>
				</details>
			) : null}
		</>
	);

	if (!onboarding) {
		return (
			<SettingsPage
				action={refresh}
				category="connections"
				description="CLI를 준비하고 사용할 agent를 연결하세요."
				title="설치 및 agent 연결"
			>
				{content}
			</SettingsPage>
		);
	}
	return (
		<TerminalPanel
			theme={theme}
			anatomy="claude"
			label="시작하기"
			className="connections-panel"
		>
			<div className="connections-heading">
				<p>CLI를 준비하고 사용할 agent를 연결하세요.</p>
				{refresh}
			</div>
			{content}
			{onDismiss ? (
				<button type="button" disabled={busy !== null} onClick={onDismiss}>
					{verified ? "시작하기" : "나중에 · Settings에서 연결"}
				</button>
			) : null}
		</TerminalPanel>
	);
}
