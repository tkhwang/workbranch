import type { CompanionTheme } from "../application/preferences";
import {
	companionRestartPending,
	type PackageVersion,
	type UpdateState,
	updateActionLabel,
	updateTargets,
} from "../application/updates";
import { ProgressButton } from "./ProgressButton";
import { TerminalPanel } from "./TerminalPanel";

type Props = {
	readonly theme: CompanionTheme;
	readonly state: UpdateState;
	readonly onCheck: () => void;
	readonly onApply: () => void;
	readonly onClose: () => void;
};

function versionBadge(version: PackageVersion): string {
	if (version.latest === null) return "확인 불가";
	if (version.installed === null) return "Homebrew 미설치";
	return version.outdated ? "업데이트 있음" : "최신";
}

function versionLine(version: PackageVersion): string {
	const installed = version.installed ?? "없음";
	const latest = version.latest ?? "알 수 없음";
	return version.outdated
		? `설치 ${installed} → 최신 ${latest}`
		: `설치 ${installed} · 최신 ${latest}`;
}

export function UpdatePanel({
	theme,
	state,
	onCheck,
	onApply,
	onClose,
}: Props) {
	const { status, checking, updating, restarting } = state;
	const busy = checking || updating || restarting;
	const targets = updateTargets(status);
	return (
		<TerminalPanel
			theme={theme}
			anatomy="claude"
			label="업데이트"
			className="connections-panel update-panel"
		>
			<div className="connections-heading">
				<p>Homebrew로 설치한 CLI와 Companion의 최신 버전을 확인합니다.</p>
				<div className="connection-actions">
					<ProgressButton
						pending={checking}
						pendingLabel="확인 중…"
						disabled={busy}
						onClick={onCheck}
					>
						다시 확인
					</ProgressButton>
					<button type="button" disabled={updating} onClick={onClose}>
						닫기
					</button>
				</div>
			</div>
			{state.error ? (
				<p role="alert" className="error">
					{state.error}
				</p>
			) : null}
			{state.notice ? <p role="status">{state.notice}</p> : null}
			{status?.fetchError ? (
				<p className="settings-hint">
					Homebrew 정보를 갱신하지 못해 최신 버전이 오래됐을 수 있습니다:{" "}
					{status.fetchError}
				</p>
			) : null}
			{status ? (
				status.brewPath === null ? (
					<p className="settings-hint">
						Homebrew를 찾지 못했습니다. 실행 중인 Companion{" "}
						{status.runningVersion}
					</p>
				) : (
					<>
						<section className="connection-step" aria-label="CLI version">
							<header>
								<strong>Workbranch CLI</strong>
								<span className="connection-badge">
									{versionBadge(status.cli)}
								</span>
							</header>
							<p>{versionLine(status.cli)}</p>
							{status.cli.installed === null && status.cli.latest !== null ? (
								<p className="settings-hint">
									Settings의 설치 및 agent 연결에서 CLI를 설치하세요.
								</p>
							) : null}
						</section>
						<section className="connection-step" aria-label="Companion version">
							<header>
								<strong>Workbranch Companion</strong>
								<span className="connection-badge">
									{versionBadge(status.companion)}
								</span>
							</header>
							<p>
								실행 중 {status.runningVersion} ·{" "}
								{versionLine(status.companion)}
							</p>
							{!status.selfUpdateSupported ? (
								<p className="settings-hint">
									개발 빌드에서는 Companion을 업데이트하지 않습니다.
								</p>
							) : companionRestartPending(status) ? (
								<p className="settings-hint">
									새 버전이 설치되어 있습니다. Companion을 다시 시작하면
									적용됩니다.
								</p>
							) : null}
						</section>
						{targets.length > 0 ? (
							<div className="connection-actions">
								<ProgressButton
									pending={updating || restarting}
									pendingLabel={restarting ? "재시작 중…" : "업데이트 중…"}
									disabled={busy}
									onClick={onApply}
								>
									{updateActionLabel(targets)}
								</ProgressButton>
							</div>
						) : !checking ? (
							<p role="status">업데이트할 항목이 없습니다.</p>
						) : null}
					</>
				)
			) : checking ? (
				<p role="status">최신 버전을 확인하고 있습니다…</p>
			) : null}
			{updating ? (
				<p role="status">Homebrew 업데이트 중… 완료될 때까지 기다려 주세요.</p>
			) : null}
			{state.logs ? (
				<details className="connection-logs">
					<summary>상세 로그</summary>
					<pre>{state.logs}</pre>
				</details>
			) : null}
		</TerminalPanel>
	);
}
