import { useState } from "react";
import type { ConnectionState, SetupAction } from "../application/connections";
import { cliSetupAction, receiptState } from "../application/connections";
import type { CompanionTheme } from "../application/preferences";
import type { AgentSession } from "../domain/model";
import { formatRelativeTime } from "./TaskRow";
import { TerminalPanel } from "./TerminalPanel";

const names = { claude: "Claude Code", codex: "Codex", grok: "Grok Build" };
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
		<fieldset
			className="agent-connection grok-trust-prompt"
			aria-label="Grok plugin 설치 승인"
		>
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
	const ready = status?.cli.state === "ready";
	const verified =
		status?.agents.some(
			(agent) =>
				agent.state === "configured" &&
				receiptState(
					Math.max(
						agent.lastObservedAt ?? 0,
						...sessions
							.filter((s) => s.provider === agent.provider)
							.map((s) => s.updatedAt),
					),
					state.verificationAfter[agent.provider],
				) === "verified",
		) ?? false;
	return (
		<TerminalPanel
			theme={theme}
			anatomy="claude"
			label={onboarding ? "시작하기" : "설치 및 agent 연결"}
			className="connections-panel"
		>
			<div className="connections-heading">
				<p>CLI를 준비하고 사용할 agent를 연결하세요.</p>
				<button
					type="button"
					disabled={loading || busy !== null}
					onClick={onRefresh}
				>
					{loading ? "확인 중…" : "다시 확인"}
				</button>
			</div>
			{state.error ? (
				<p role="alert" className="error">
					{state.error}
				</p>
			) : null}
			{state.notice ? <p role="status">{state.notice}</p> : null}
			{status ? (
				<>
					<section className="connection-step" aria-label="Install CLI">
						<header>
							<strong>1 · Workbranch CLI</strong>
							<span className="connection-badge">
								{ready
									? "준비됨"
									: status.cli.state === "missing"
										? "미설치"
										: "확인 필요"}
							</span>
						</header>
						<p>{status.cli.message}</p>
						<div className="connection-actions">
							<button
								type="button"
								disabled={!status.brewPath || busy !== null}
								onClick={() =>
									onAction({
										kind: cliSetupAction(status),
									})
								}
							>
								{cliSetupAction(status) === "installCli"
									? "CLI 설치"
									: cliSetupAction(status) === "repairCli"
										? "설치 복구"
										: "CLI 업데이트"}
							</button>
							{ready && status.formulaInstalled === true ? (
								<button
									type="button"
									disabled={!status.brewPath || busy !== null}
									onClick={() => onAction({ kind: "repairCli" })}
								>
									설치 복구
								</button>
							) : null}
						</div>
						{!status.brewPath ? (
							<p className="settings-hint">
								Homebrew를 찾지 못했습니다. 설치 또는 실행 경로를 확인하세요.
							</p>
						) : null}
						<details>
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
					</section>
					<section className="connection-step" aria-label="Connect AI Agent">
						<h3>2 · AI Agent 연결</h3>
						{!ready ? (
							<p className="settings-hint">
								CLI 준비가 끝나면 agent를 연결할 수 있습니다.
							</p>
						) : null}
						{status.agents.map((agent) => {
							const seen = Math.max(
								agent.lastObservedAt ?? 0,
								...sessions
									.filter((s) => s.provider === agent.provider)
									.map((s) => s.updatedAt),
							);
							const configured = agent.state === "configured";
							const receipt = receiptState(
								seen,
								state.verificationAfter[agent.provider],
							);
							const disabled = !ready || !agent.executablePath || busy !== null;
							const missingTrustTarget =
								agent.provider === "grok" && !agent.installSource;
							const label =
								agent.state === "notInstalled"
									? "Agent 미설치"
									: agent.state === "disabled"
										? "비활성"
										: agent.state === "trustRequired"
											? "신뢰 승인 필요"
											: configured
												? "설정됨"
												: agent.state === "unknown"
													? "확인 필요"
													: "미연결";
							return (
								<article className="agent-connection" key={agent.provider}>
									<header>
										<strong>{names[agent.provider]}</strong>
										<span className="connection-badge">{label}</span>
									</header>
									<p>{agent.message}</p>
									{configured ? (
										<p className="connection-observation">
											{receipt === "verified"
												? `수신 확인됨 · 마지막 관측 ${formatRelativeTime(seen, Math.floor(Date.now() / 1000))} 전`
												: receipt === "historical"
													? `이전 수신 기록 · ${formatRelativeTime(seen, Math.floor(Date.now() / 1000))} 전 · 새 이벤트 확인 대기`
													: "첫 이벤트 수신 대기 · 설치만으로 수집 완료를 뜻하지 않습니다."}
										</p>
									) : null}
									<div className="connection-actions">
										<button
											type="button"
											disabled={disabled || missingTrustTarget}
											onClick={() => {
												if (agent.provider === "grok" && agent.installSource) {
													setTrustSource(agent.installSource);
												} else
													onAction({
														kind: "connectAgent",
														provider: agent.provider,
													});
											}}
										>
											{configured || agent.state === "disabled"
												? "다시 연결"
												: "연결"}
										</button>
										{agent.state !== "notInstalled" &&
										agent.state !== "disconnected" ? (
											<button
												type="button"
												disabled={disabled}
												onClick={() =>
													onAction({
														kind: "disconnectAgent",
														provider: agent.provider,
													})
												}
											>
												연결 해제
											</button>
										) : null}
									</div>
									{missingTrustTarget ? (
										<p className="settings-hint">
											Grok 설치 대상을 확인하려면 CLI를 업데이트하고 다시
											확인하세요.
										</p>
									) : null}
									{agent.provider === "grok" && trustSource !== null ? (
										<GrokTrustPrompt
											source={trustSource}
											disabled={disabled || agent.installSource !== trustSource}
											onCancel={() => setTrustSource(null)}
											onApprove={() => {
												if (disabled || agent.installSource !== trustSource)
													return;
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
											Agent의 /hooks에서 연결과 신뢰 상태를 확인하세요. 기존
											session은 다시 시작해야 할 수 있습니다.
										</p>
									) : null}
								</article>
							);
						})}
					</section>
				</>
			) : loading ? (
				<p role="status">설치 상태를 확인하고 있습니다…</p>
			) : (
				<p>설치 상태를 읽을 수 없습니다. 다시 확인하세요.</p>
			)}
			{busy ? (
				<p role="status">
					{busy.kind.endsWith("Agent")
						? "Agent 연결 작업 중…"
						: "Homebrew 작업 중…"}{" "}
					완료될 때까지 기다려 주세요.
				</p>
			) : null}
			{state.logs ? (
				<details className="connection-logs">
					<summary>상세 로그</summary>
					<pre>{state.logs}</pre>
				</details>
			) : null}
			{onboarding && onDismiss ? (
				<button type="button" disabled={busy !== null} onClick={onDismiss}>
					{verified ? "시작하기" : "나중에 · Settings에서 연결"}
				</button>
			) : null}
		</TerminalPanel>
	);
}
