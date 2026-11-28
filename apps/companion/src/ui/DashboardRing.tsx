// One task as a clock face on the lock screen: the last three hours run
// clockwise around the ring with now at the top. Running is a solid line,
// waiting on me a thick band, an ended turn a dotted line with a dot where the
// turn ended (crossed when it failed). The middle says what the task needs.
// Inside a large ring, each tool call is a dot at its time; recent calls are
// linked to their tool's node and to the files they touched. A compact ring
// keeps only the history, the turn starts and the middle, for a full grid.
// A new call travels from now to its tool once, as a declarative SVG
// animation: nothing schedules frames, so a quiet dashboard draws nothing.
import type { ReactNode } from "react";
import type {
	RingCall,
	RingModel,
	RingSummary,
	WaitReason,
} from "../application/ring";
import {
	RING_GAP_DEGREES,
	RING_WINDOW_SECONDS,
	ringAngle,
} from "../application/ring";
import type { HistoryState, TaskMessage } from "../application/taskHistory";
import { ProviderIcon } from "./ProviderIcon";

export type RingSize = "large" | "compact";

/** The ring's radius in viewBox units; labels and the halo sit outside it. */
const R = 200;
const VIEW = 268;
const TICK_SECONDS = 30 * 60;

/** Repo tints in the theme (`--repo-1` … `--repo-4`). */
const REPO_TONES = 4;

const STATE_LABELS: Readonly<Record<HistoryState, string>> = {
	running: "실행 중",
	waiting: "내 응답 대기",
	finished: "턴 종료",
};

const WAIT_LABELS: Readonly<Record<string, string>> = {
	question: "질문",
	permission: "권한 요청",
	plan: "계획 승인",
	elicitation: "입력 요청",
};

/**
 * A repo's tint, 1 to REPO_TONES. Taken from its name, so a repo keeps its
 * color on every ring and across restarts, whatever else is on screen.
 */
export function repoTone(name: string): number {
	let hash = 0;
	for (const char of name)
		hash = (hash * 31 + (char.codePointAt(0) ?? 0)) >>> 0;
	return (hash % REPO_TONES) + 1;
}

/** Seconds as "12m" or "1h 05m", for time in state. */
export function formatElapsed(seconds: number): string {
	const minutes = Math.max(0, Math.floor(seconds / 60));
	if (minutes < 60) return `${minutes}m`;
	return `${Math.floor(minutes / 60)}h ${String(minutes % 60).padStart(2, "0")}m`;
}

/** How long ago: "방금", "12분 전", "3시간 전", "2일 전". */
export function formatAgo(at: number, now: number): string {
	const minutes = Math.floor(Math.max(0, now - at) / 60);
	if (minutes < 1) return "방금";
	if (minutes < 60) return `${minutes}분 전`;
	const hours = Math.floor(minutes / 60);
	if (hours < 24) return `${hours}시간 전`;
	return `${Math.floor(hours / 24)}일 전`;
}

const TEST_MARKS: Readonly<Record<RingSummary["tests"], string>> = {
	passed: "✓",
	failed: "✗",
	unknown: "?",
	none: "–",
};

const TEST_LABELS: Readonly<Record<RingSummary["tests"], string>> = {
	passed: "tests passed",
	failed: "tests failed",
	unknown: "tests ran",
	none: "no tests run",
};

/** One line for an ended turn: "4 files · +530 −133 · tests ✓ · 1 commit". */
export function summaryLine(summary: RingSummary): string {
	return [
		`${summary.filesChanged} ${summary.filesChanged === 1 ? "file" : "files"}`,
		`+${summary.linesAdded} −${summary.linesRemoved}`,
		`tests ${TEST_MARKS[summary.tests]}`,
		`${summary.commits} ${summary.commits === 1 ? "commit" : "commits"}`,
	].join(" · ");
}

/** At most `limit` characters, with an ellipsis when cut. */
export function shorten(text: string, limit: number): string {
	const chars = Array.from(text);
	return chars.length > limit ? `${chars.slice(0, limit - 1).join("")}…` : text;
}

/** Why the task waits, in words; the reason alone when the collector gives a new one. */
export function waitLabel(reason: WaitReason): string {
	return WAIT_LABELS[reason] ?? reason;
}

function point(radius: number, degrees: number): readonly [number, number] {
	const rad = (degrees * Math.PI) / 180;
	return [
		Number((radius * Math.cos(rad)).toFixed(2)),
		Number((radius * Math.sin(rad)).toFixed(2)),
	];
}

/** Where a call's dot sits: just inside the ring, staggered so neighbours show. */
function callPoint(call: RingCall, index: number): readonly [number, number] {
	return point(R * (0.9 - (index % 3) * 0.04), call.angle);
}

/** A tool node's radius: grows with its calls, slower than linearly. */
export function hubRadius(count: number): number {
	return 4 + Math.sqrt(count) * 1.6;
}

/** A clockwise arc on the ring; empty when it has no length. */
export function arcPath(radius: number, from: number, to: number): string {
	if (to - from <= 0.05) return "";
	const [x0, y0] = point(radius, from);
	const [x1, y1] = point(radius, to);
	return `M${x0} ${y0} A${radius} ${radius} 0 ${to - from > 180 ? 1 : 0} 1 ${x1} ${y1}`;
}

/** Half hours back from now, now included, across one turn of the ring. */
const TICKS: readonly number[] = Array.from(
	{ length: RING_WINDOW_SECONDS / TICK_SECONDS + 1 },
	(_, i) => i * TICK_SECONDS,
);

// Whole hours carry a label; three hours ago would sit on top of now.
function tickLabel(secondsAgo: number): string | null {
	if (secondsAgo === 0) return "지금";
	if (secondsAgo % 3600 !== 0 || secondsAgo >= RING_WINDOW_SECONDS) return null;
	return `${secondsAgo / 3600}시간 전`;
}

function Ticks({ now, labels }: { now: number; labels: boolean }) {
	return (
		<g className="ring-ticks">
			{TICKS.map((secondsAgo) => {
				const angle = ringAngle(now - secondsAgo, now);
				const [x0, y0] = point(R - 7, angle);
				const [x1, y1] = point(R + 7, angle);
				const [lx, ly] = point(R + 42, angle);
				const label = labels ? tickLabel(secondsAgo) : null;
				return (
					<g key={secondsAgo}>
						<line className="ring-tick" x1={x0} x2={x1} y1={y0} y2={y1} />
						{label === null ? null : (
							<text
								className="ring-tick-label"
								textAnchor="middle"
								x={lx}
								y={ly + 5}
							>
								{label}
							</text>
						)}
					</g>
				);
			})}
		</g>
	);
}

/** The gap between todo segments on the outer progress ring. */
const PROGRESS_GAP_DEGREES = 3;

// The todo list as segments just outside the ring, one per todo in order:
// done ones lit, the next one breathing while the task runs, the rest faint.
function Progress({ ring }: { ring: RingModel }) {
	const progress = ring.progress;
	if (progress === undefined) return null;
	const span = (360 - RING_GAP_DEGREES) / progress.total;
	const start = -90 + RING_GAP_DEGREES / 2;
	const segments = Array.from({ length: progress.total }, (_, index) => ({
		from: start + index * span + PROGRESS_GAP_DEGREES / 2,
		status:
			index < progress.done
				? "done"
				: index === progress.done && ring.state === "running"
					? "active"
					: "todo",
	}));
	return (
		<g className="ring-progress">
			{segments.map(({ from, status }) => (
				<path
					className="ring-progress-segment"
					d={arcPath(R + 20, from, from + span - PROGRESS_GAP_DEGREES)}
					data-status={status}
					key={from}
				/>
			))}
		</g>
	);
}

// The work inside a large ring: links first, so dots and nodes sit on top.
function Work({ ring }: { ring: RingModel }) {
	const [nx, ny] = point(R, ring.nowAngle);
	const hubAt = new Map(
		ring.hubs.map((hub) => [hub.group, point(R * 0.5, hub.angle)] as const),
	);
	const fileAt = new Map(
		ring.files.map((file) => [file.name, point(R * 0.7, file.angle)] as const),
	);
	const placed = ring.calls.map((call, index) => ({
		call,
		at: callPoint(call, index),
		key: `${call.angle}:${index}`,
	}));
	return (
		<g className="ring-work">
			{placed
				.filter(({ call }) => call.recent)
				.map(({ call, at: [x, y], key }) => {
					const hub = hubAt.get(call.group);
					return (
						<g key={key}>
							{hub === undefined ? null : (
								<path
									className="ring-link"
									d={`M${x} ${y} Q${((x + hub[0]) / 2) * 0.75} ${((y + hub[1]) / 2) * 0.75} ${hub[0]} ${hub[1]}`}
								/>
							)}
							{call.files.map((name) => {
								const file = fileAt.get(name);
								return file === undefined ? null : (
									<line
										className="ring-file-link"
										key={name}
										x1={x}
										x2={file[0]}
										y1={y}
										y2={file[1]}
									/>
								);
							})}
						</g>
					);
				})}
			{placed.map(({ call, at: [x, y], key }) =>
				call.failed ? (
					<path
						className="ring-call"
						d={`M${x - 3} ${y - 3}l6 6M${x + 3} ${y - 3}l-6 6`}
						data-failed="true"
						key={key}
					/>
				) : (
					<circle
						className="ring-call"
						cx={x}
						cy={y}
						data-recent={call.recent ? "true" : undefined}
						key={key}
						r={2.2}
					/>
				),
			)}
			{placed
				.filter(({ call }) => call.fresh)
				.map(({ call, at: [x, y] }) => {
					const hub = hubAt.get(call.group);
					if (hub === undefined) return null;
					const path = `M${nx} ${ny} L${x} ${y} Q${((x + hub[0]) / 2) * 0.75} ${((y + hub[1]) / 2) * 0.75} ${hub[0]} ${hub[1]}`;
					return (
						<circle
							className="ring-comet"
							data-failed={call.failed ? "true" : undefined}
							key={`comet:${call.at}:${call.group}`}
							r={4.5}
						>
							<animateMotion dur="1.2s" fill="freeze" path={path} />
							<animate
								attributeName="opacity"
								dur="1.2s"
								fill="freeze"
								values="1;1;0"
							/>
						</circle>
					);
				})}
			{ring.hubs.map((hub) => {
				const [x, y] = point(R * 0.5, hub.angle);
				const radius = hubRadius(hub.count);
				const [lx, ly] = point(R * 0.5 + radius + 8, hub.angle);
				return (
					<g className="ring-hub" key={hub.group}>
						<circle cx={x} cy={y} r={radius} />
						<text
							textAnchor={lx < -5 ? "end" : lx > 5 ? "start" : "middle"}
							x={lx}
							y={ly + 5}
						>
							{hub.group}
						</text>
					</g>
				);
			})}
			{ring.files.map((file) => {
				const [x, y] = point(R * 0.7, file.angle);
				return (
					<g className="ring-file" key={file.name}>
						<rect height={7} width={7} x={x - 3.5} y={y - 3.5} />
						<text
							textAnchor={x < 0 ? "end" : "start"}
							x={x + (x < 0 ? -9 : 9)}
							y={y + 4}
						>
							{file.name}
						</text>
					</g>
				);
			})}
		</g>
	);
}

function SummaryCell({
	x,
	y,
	label,
	tests,
	children,
}: {
	x: number;
	y: number;
	label: string;
	tests?: RingSummary["tests"];
	children: ReactNode;
}) {
	return (
		<g className="ring-summary-cell" data-tests={tests}>
			<text className="ring-summary-value" textAnchor="middle" x={x} y={y}>
				{children}
			</text>
			<text className="ring-summary-label" textAnchor="middle" x={x} y={y + 14}>
				{label}
			</text>
		</g>
	);
}

function Middle({
	ring,
	now,
	size,
}: {
	ring: RingModel;
	now: number;
	size: RingSize;
}) {
	const large = size === "large";
	const progress = ring.progress;
	const failed = ring.failed;
	if (ring.state === "waiting")
		return (
			<g className="ring-middle" data-state="waiting">
				<text
					className="ring-middle-title"
					textAnchor="middle"
					y={large ? -6 : 8}
				>
					응답 대기
				</text>
				<text
					className="ring-middle-detail"
					textAnchor="middle"
					y={large ? 26 : 44}
				>
					{[waitLabel(ring.waitReason), formatElapsed(now - ring.since)]
						.filter(Boolean)
						.join(" · ")}
				</text>
				{large && progress !== undefined ? (
					<text className="ring-middle-label" textAnchor="middle" y={54}>
						todos {progress.done}/{progress.total}
					</text>
				) : null}
			</g>
		);
	if (ring.state === "running" && progress !== undefined)
		return (
			<g className="ring-middle" data-state="running">
				<text
					className="ring-middle-value"
					textAnchor="middle"
					y={large ? 6 : 24}
				>
					{progress.done}
					<tspan className="ring-middle-of">/{progress.total}</tspan>
				</text>
				{large ? (
					<text className="ring-middle-label" textAnchor="middle" y={32}>
						TODOS DONE
					</text>
				) : null}
				{large && progress.active !== undefined ? (
					<text className="ring-middle-active" textAnchor="middle" y={58}>
						▸ {shorten(progress.active, 24)}
					</text>
				) : null}
			</g>
		);
	if (ring.state === "running")
		return (
			<g className="ring-middle" data-state="running">
				<text
					className="ring-middle-value"
					textAnchor="middle"
					y={large ? 14 : 24}
				>
					{formatElapsed(now - ring.since)}
				</text>
				{large ? (
					<text className="ring-middle-detail" textAnchor="middle" y={46}>
						{ring.recentCalls > 0
							? `${ring.recentCalls} calls · 30m`
							: "실행 중"}
					</text>
				) : null}
			</g>
		);
	const summary = ring.summary;
	if (large && summary !== undefined)
		return (
			<g
				className="ring-middle"
				data-error={failed ? "true" : undefined}
				data-state="finished"
			>
				<circle className="ring-summary-ground" r={R * 0.62} />
				<g transform="scale(1.5)">
					<text className="ring-middle-title" textAnchor="middle" y={-36}>
						{failed ? "✕ 오류로 끝남" : "✓ 턴 종료"}
					</text>
					<text className="ring-middle-label" textAnchor="middle" y={-18}>
						{formatAgo(ring.since, now)}
						{progress === undefined
							? ""
							: ` · todos ${progress.done}/${progress.total}`}
					</text>
					<SummaryCell
						label={
							summary.filesChanged === 1 ? "file changed" : "files changed"
						}
						x={-38}
						y={12}
					>
						{summary.filesChanged}
					</SummaryCell>
					<SummaryCell label="lines" x={38} y={12}>
						<tspan className="ring-summary-added">+{summary.linesAdded}</tspan>{" "}
						<tspan className="ring-summary-removed">
							−{summary.linesRemoved}
						</tspan>
					</SummaryCell>
					<SummaryCell
						label={TEST_LABELS[summary.tests]}
						tests={summary.tests}
						x={-38}
						y={48}
					>
						{TEST_MARKS[summary.tests]}
					</SummaryCell>
					<SummaryCell
						label={summary.commits === 1 ? "commit" : "commits"}
						x={38}
						y={48}
					>
						{summary.commits}
					</SummaryCell>
				</g>
			</g>
		);
	return (
		<g
			className="ring-middle"
			data-error={failed ? "true" : undefined}
			data-state="finished"
		>
			<text
				className="ring-middle-title"
				textAnchor="middle"
				y={large ? -6 : 8}
			>
				{failed ? "✕ 오류로 끝남" : "✓ 턴 종료"}
			</text>
			<text
				className="ring-middle-detail"
				textAnchor="middle"
				y={large ? 26 : 44}
			>
				{formatAgo(ring.since, now)}
			</text>
		</g>
	);
}

function Face({
	ring,
	now,
	size,
}: {
	ring: RingModel;
	now: number;
	size: RingSize;
}) {
	const [nx, ny] = point(R, ring.nowAngle);
	return (
		<svg
			aria-hidden="true"
			className="ring-face"
			viewBox={`${-VIEW} ${-VIEW} ${VIEW * 2} ${VIEW * 2}`}
		>
			{ring.state === "waiting" ? (
				<circle className="ring-halo" r={R + 30} />
			) : null}
			<path
				className="ring-track"
				d={arcPath(R, ringAngle(now - RING_WINDOW_SECONDS, now), ring.nowAngle)}
			/>
			<Ticks labels={size === "large"} now={now} />
			<Progress ring={ring} />
			{ring.arcs.map((arc) => (
				<path
					className="ring-arc"
					d={arcPath(R, arc.from, arc.to)}
					data-state={arc.state}
					key={`${arc.state}:${arc.from}`}
				/>
			))}
			{size === "large" ? <Work ring={ring} /> : null}
			{ring.turnStarts.map((turn) => {
				const [x, y] = point(R, turn.angle);
				return (
					<circle
						className="ring-turn-start"
						cx={x}
						cy={y}
						data-kind={turn.kind}
						key={`${turn.kind}:${turn.angle}`}
						r={size === "large" ? 6.5 : 9}
					/>
				);
			})}
			{ring.turnEnds.map((end) => {
				const [x, y] = point(R, end.angle);
				return end.error ? (
					<path
						className="ring-turn-end"
						d={`M${x - 7} ${y - 7}l14 14M${x + 7} ${y - 7}l-14 14`}
						data-error="true"
						key={end.angle}
					/>
				) : (
					<circle
						className="ring-turn-end"
						cx={x}
						cy={y}
						key={end.angle}
						r={7}
					/>
				);
			})}
			{ring.state === "running" ? (
				<circle className="ring-pulse" cx={nx} cy={ny} r={8} />
			) : null}
			<circle
				className="ring-now"
				cx={nx}
				cy={ny}
				data-state={ring.state}
				r={6}
			/>
			<circle className="ring-middle-ground" r={R * 0.4} />
			<Middle now={now} ring={ring} size={size} />
		</svg>
	);
}

const MESSAGE_LABELS: Readonly<Record<TaskMessage["kind"], string>> = {
	prompt: "Human",
	response: "AI",
	commit: "Commit",
};

// Work details under a large ring's name: what it does now, and its newest
// request, reply or commit. The model leaves both out unless Settings asks.
function Details({ ring, now }: { ring: RingModel; now: number }) {
	return (
		<>
			{ring.activity === undefined ? null : (
				<span className="ring-activity">▸ {ring.activity}</span>
			)}
			{ring.message === undefined ? null : (
				<span className="ring-message">
					<span className="ring-message-kind" data-kind={ring.message.kind}>
						{MESSAGE_LABELS[ring.message.kind]}
					</span>
					<span className="ring-message-text">{ring.message.text}</span>
					<span className="ring-message-ago">
						{formatAgo(ring.message.at, now)}
					</span>
				</span>
			)}
		</>
	);
}

/** Short agent names: the pill has room for a word, not a product name. */
const AGENT_NAMES: Readonly<Record<RingModel["agents"][number], string>> = {
	claude: "Claude",
	codex: "Codex",
	grok: "Grok",
};

/** The pill's state: an ended turn that failed reads as its own state. */
export function pillState(ring: RingModel): HistoryState | "error" {
	return ring.failed ? "error" : ring.state;
}

const PILL_LABELS: Readonly<Record<HistoryState | "error", string>> = {
	...STATE_LABELS,
	error: "오류로 끝남",
};

// Who works and how it goes, kept apart in one pill: the left half names the
// agents by shape and name only, in no color, so any number of agents never
// clashes with a state; the right half carries the state in color, a dot
// shape and words, with the time in it.
function Pill({ ring, now }: { ring: RingModel; now: number }) {
	const state = pillState(ring);
	return (
		<span className="ring-pill" data-state={state}>
			{ring.agents.length === 0 ? null : (
				<span className="ring-pill-agent">
					<span className="ring-pill-icons">
						{ring.agents.map((agent) => (
							<ProviderIcon key={agent} provider={agent} />
						))}
					</span>
					{ring.agents.map((agent) => AGENT_NAMES[agent]).join(" + ")}
				</span>
			)}
			<span className="ring-pill-status">
				<span aria-hidden="true" className="ring-pill-dot" />
				{PILL_LABELS[state]}
				<span className="ring-pill-time">
					{formatElapsed(now - ring.since)}
				</span>
			</span>
		</span>
	);
}

// Above the ring, what the task is and how it goes: the agent and state pill,
// then the worktree branch and repo.
function Title({ ring, now }: { ring: RingModel; now: number }) {
	return (
		<header className="ring-title">
			<Pill now={now} ring={ring} />
			<span className="ring-branchline">
				<span className="ring-name">{ring.title}</span>
				{ring.repo === undefined ? null : (
					<span className="ring-repo">
						<span className="ring-repo-name" data-tone={repoTone(ring.repo)}>
							{ring.repo}
						</span>
						{ring.moreRepos > 0 ? (
							<span className="ring-repo-more"> +{ring.moreRepos}</span>
						) : null}
					</span>
				)}
			</span>
		</header>
	);
}

// Below a large ring, the work details Settings allows; the state itself is
// in the pill above.
function Caption({ ring, now }: { ring: RingModel; now: number }) {
	return (
		<div className="ring-caption">
			<Details now={now} ring={ring} />
		</div>
	);
}

export function DashboardRing({
	ring,
	now,
	size,
}: {
	readonly ring: RingModel;
	/** Epoch seconds. */
	readonly now: number;
	readonly size: RingSize;
}) {
	return (
		<article
			aria-label={`${ring.title} · ${STATE_LABELS[ring.state]}`}
			className="ring"
			data-size={size}
			data-state={ring.state}
		>
			<Title now={now} ring={ring} />
			<Face now={now} ring={ring} size={size} />
			{size === "large" ? <Caption now={now} ring={ring} /> : null}
		</article>
	);
}
