import type { CSSProperties } from "react";
import { useEffect, useMemo, useState } from "react";
import { IDLE_GAP_SECONDS } from "../application/activity";
import {
	addDays,
	type CalendarEventInput,
	type CalendarSession,
	clipToRange,
	hourRange,
	type LaneSession,
	projectColorIndex,
	sessionsFromEvents,
	startOfDayEpoch,
} from "./calendar";
import { assignDisplayLanes } from "./displaySessions";

export { assignDisplayLanes } from "./displaySessions";

export type CalendarMode = "day" | "three-day";

type CalendarModeOption = {
	readonly mode: CalendarMode;
	readonly label: string;
	readonly ariaLabel: string;
};

export const CALENDAR_MODES: readonly CalendarModeOption[] = [
	{ mode: "day", label: "Day", ariaLabel: "Day view" },
	{ mode: "three-day", label: "3d", ariaLabel: "Three day view" },
];

type ActivityCalendarViewProps = {
	readonly loadEvents: (
		fromEpoch: number,
		toEpoch: number,
	) => Promise<readonly CalendarEventInput[]>;
	readonly reloadToken: number;
	readonly today: () => Date;
};

type ActivityLoadRange = {
	readonly from: number;
	readonly to: number;
};

type CalendarTimelineProps = {
	readonly days: readonly number[];
	readonly sessions: readonly LaneSession[];
	readonly mode: CalendarMode;
	readonly selectedKey: string | undefined;
	readonly onSelect: (key: string | undefined) => void;
};

const SECONDS_PER_HOUR = 60 * 60;
const PALETTE_SIZE = 6;

function modeDays(mode: CalendarMode): number {
	switch (mode) {
		case "day":
			return 1;
		case "three-day":
			return 3;
	}
}

function dateFromEpoch(epoch: number): Date {
	return new Date(epoch * 1000);
}

function formatHour(hour: number): string {
	const normalized = ((hour % 24) + 24) % 24;
	if (normalized === 0) {
		return "12 AM";
	}
	if (normalized < 12) {
		return `${normalized} AM`;
	}
	if (normalized === 12) {
		return "12 PM";
	}
	return `${normalized - 12} PM`;
}

function formatTime(epoch: number): string {
	const date = dateFromEpoch(epoch);
	const hours = String(date.getHours()).padStart(2, "0");
	const minutes = String(date.getMinutes()).padStart(2, "0");
	return `${hours}:${minutes}`;
}

function formatDateLabel(epoch: number): string {
	return new Intl.DateTimeFormat("en-US", {
		month: "short",
		day: "numeric",
	}).format(dateFromEpoch(epoch));
}

function formatDayLabel(epoch: number): string {
	return new Intl.DateTimeFormat("en-US", {
		weekday: "short",
		day: "numeric",
	}).format(dateFromEpoch(epoch));
}

function formatFullDayLabel(epoch: number): string {
	return new Intl.DateTimeFormat("en-US", {
		weekday: "short",
		month: "short",
		day: "numeric",
	}).format(dateFromEpoch(epoch));
}

function periodLabel(
	anchorEpoch: number,
	mode: CalendarMode,
	today: Date,
): string {
	if (mode === "day") {
		const label = formatFullDayLabel(anchorEpoch);
		return startOfDayEpoch(today) === anchorEpoch
			? `Today, ${formatDateLabel(anchorEpoch)}`
			: label;
	}
	const endEpoch = addDays(anchorEpoch, modeDays(mode) - 1);
	return `${formatDateLabel(anchorEpoch)} – ${formatDateLabel(endEpoch)}`;
}

function CalendarModeIcon({ mode }: { readonly mode: CalendarMode }) {
	if (mode === "day") {
		return (
			<svg aria-hidden="true" className="cal-mode-icon" viewBox="0 0 24 24">
				<rect x="9" y="4" width="6" height="16" rx="1" />
			</svg>
		);
	}
	return (
		<svg aria-hidden="true" className="cal-mode-icon" viewBox="0 0 24 24">
			<rect x="4" y="5" width="4" height="14" rx="1" />
			<rect x="10" y="4" width="4" height="16" rx="1" />
			<rect x="16" y="5" width="4" height="14" rx="1" />
		</svg>
	);
}

function timelineHours(startHour: number, endHour: number): readonly number[] {
	const hours: number[] = [];
	for (let hour = startHour; hour < endHour; hour += 1) {
		hours.push(hour);
	}
	return hours;
}

function styleForSession(
	session: LaneSession,
	dayStart: number,
	startHour: number,
	endHour: number,
): CSSProperties {
	const rangeSeconds = Math.max(
		SECONDS_PER_HOUR,
		(endHour - startHour) * SECONDS_PER_HOUR,
	);
	const dayEnd = addDays(dayStart, 1);
	const visibleStart = Math.max(
		session.start,
		dayStart + startHour * SECONDS_PER_HOUR,
	);
	const visibleEnd = Math.min(
		session.end,
		dayEnd,
		dayStart + endHour * SECONDS_PER_HOUR,
	);
	const top =
		((visibleStart - dayStart - startHour * SECONDS_PER_HOUR) / rangeSeconds) *
		100;
	const height = Math.max(
		3,
		((visibleEnd - visibleStart) / rangeSeconds) * 100,
	);
	const laneCount = Math.max(1, session.laneCount);
	const width = 100 / laneCount;
	return {
		top: `${top}%`,
		height: `${height}%`,
		left: `${session.lane * width}%`,
		width: `${width}%`,
	};
}

function timeRange(session: CalendarSession): string {
	return `${formatTime(session.start)}–${formatTime(session.end)}`;
}

function sessionDensity(session: CalendarSession): "compact" | "regular" {
	return session.end - session.start < 30 * 60 ? "compact" : "regular";
}

function sessionWidth(session: LaneSession): "narrow" | "wide" {
	return session.laneCount > 1 ? "narrow" : "wide";
}

function daySessions(
	sessions: readonly LaneSession[],
	dayStart: number,
): readonly LaneSession[] {
	const dayEnd = addDays(dayStart, 1);
	return sessions.filter(
		(session) => session.end > dayStart && session.start < dayEnd,
	);
}

export function activityLoadRange(
	anchorEpoch: number,
	rangeEnd: number,
): ActivityLoadRange {
	return {
		from: anchorEpoch - IDLE_GAP_SECONDS,
		to: rangeEnd + IDLE_GAP_SECONDS,
	};
}

export function CalendarTimeline({
	days,
	sessions,
	mode,
	selectedKey,
	onSelect,
}: CalendarTimelineProps) {
	const range = hourRange(sessions);
	const hours = timelineHours(range.startHour, range.endHour);
	return (
		<div className="cal-timeline" data-mode={mode}>
			<div className="cal-hours" aria-hidden="true">
				{hours.map((hour) => (
					<span className="cal-hour-label" key={hour}>
						{formatHour(hour)}
					</span>
				))}
			</div>
			<div
				className="cal-days"
				style={{
					gridTemplateColumns: `repeat(${days.length}, minmax(0, 1fr))`,
				}}
			>
				{days.map((dayStart) => (
					<div className="cal-day-column" key={dayStart}>
						{mode === "three-day" ? (
							<div className="cal-day-heading">{formatDayLabel(dayStart)}</div>
						) : null}
						<div className="cal-day-grid" aria-hidden="true">
							{hours.map((hour) => (
								<span className="cal-hour-rule" key={hour} />
							))}
						</div>
						{daySessions(sessions, dayStart).map((session) => (
							<button
								aria-pressed={selectedKey === session.key}
								className="cal-session"
								data-color={projectColorIndex(session.project, PALETTE_SIZE)}
								data-density={sessionDensity(session)}
								data-selected={selectedKey === session.key ? "true" : "false"}
								data-width={sessionWidth(session)}
								key={`${dayStart}\u0000${session.key}`}
								onClick={() =>
									onSelect(
										selectedKey === session.key ? undefined : session.key,
									)
								}
								style={styleForSession(
									session,
									dayStart,
									range.startHour,
									range.endHour,
								)}
								type="button"
							>
								<span className="cal-block-task">{session.task}</span>
								{mode === "day" ? (
									<span className="cal-block-time">{timeRange(session)}</span>
								) : null}
							</button>
						))}
					</div>
				))}
			</div>
		</div>
	);
}

function projectNames(
	events: readonly CalendarEventInput[],
): readonly string[] {
	return [...new Set(events.map((event) => event.project))].sort();
}

export function validateProjectFilter(
	events: readonly CalendarEventInput[],
	selectedProject: string | undefined,
): string | undefined {
	if (selectedProject === undefined) {
		return undefined;
	}
	return events.some((event) => event.project === selectedProject)
		? selectedProject
		: undefined;
}

export function ActivityCalendarView({
	loadEvents,
	reloadToken,
	today,
}: ActivityCalendarViewProps) {
	const [mode, setMode] = useState<CalendarMode>("day");
	const [anchorEpoch, setAnchorEpoch] = useState(() =>
		startOfDayEpoch(today()),
	);
	const [events, setEvents] = useState<readonly CalendarEventInput[]>([]);
	const [loading, setLoading] = useState(true);
	const [error, setError] = useState<string>();
	const [selectedProject, setSelectedProject] = useState<string>();
	const [selectedKey, setSelectedKey] = useState<string>();
	const days = useMemo(
		() =>
			Array.from({ length: modeDays(mode) }, (_, index) =>
				addDays(anchorEpoch, index),
			),
		[anchorEpoch, mode],
	);
	const rangeEnd = addDays(anchorEpoch, modeDays(mode));
	const loadRange = useMemo(
		() => ({
			...activityLoadRange(anchorEpoch, rangeEnd),
			reloadToken,
		}),
		[anchorEpoch, rangeEnd, reloadToken],
	);

	useEffect(() => {
		let cancelled = false;
		setLoading(true);
		setError(undefined);
		void loadEvents(loadRange.from, loadRange.to)
			.then((nextEvents) => {
				if (!cancelled) {
					setEvents(nextEvents);
					setSelectedProject((currentProject) =>
						validateProjectFilter(nextEvents, currentProject),
					);
					setSelectedKey(undefined);
				}
			})
			.catch((loadError) => {
				if (!cancelled) {
					setError(
						loadError instanceof Error ? loadError.message : String(loadError),
					);
					setEvents([]);
				}
			})
			.finally(() => {
				if (!cancelled) {
					setLoading(false);
				}
			});
		return () => {
			cancelled = true;
		};
	}, [loadEvents, loadRange]);

	const projects = projectNames(events);
	const filteredEvents =
		selectedProject === undefined
			? events
			: events.filter((event) => event.project === selectedProject);
	const calendarSessions = assignDisplayLanes(
		clipToRange(sessionsFromEvents(filteredEvents), anchorEpoch, rangeEnd),
	);
	const selectedSession = calendarSessions.find(
		(session) => session.key === selectedKey,
	);
	const periodDays = modeDays(mode);
	return (
		<div className="activity-calendar">
			<div className="cal-header">
				<div className="cal-period-nav">
					<button
						aria-label="Previous period"
						className="cal-nav-button"
						onClick={() =>
							setAnchorEpoch((current) => addDays(current, -periodDays))
						}
						type="button"
					>
						‹
					</button>
					<div className="cal-title">
						{periodLabel(anchorEpoch, mode, today())}
					</div>
					<button
						aria-label="Next period"
						className="cal-nav-button"
						onClick={() =>
							setAnchorEpoch((current) => addDays(current, periodDays))
						}
						type="button"
					>
						›
					</button>
					<button
						aria-label="Go to today"
						className="cal-today-button"
						onClick={() => setAnchorEpoch(startOfDayEpoch(today()))}
						type="button"
					>
						Today
					</button>
				</div>
				<div className="cal-mode-toggle">
					{CALENDAR_MODES.map((item) => (
						<button
							aria-label={item.ariaLabel}
							aria-pressed={mode === item.mode}
							className="cal-mode-button"
							data-active={mode === item.mode ? "true" : "false"}
							key={item.mode}
							onClick={() => setMode(item.mode)}
							type="button"
						>
							<CalendarModeIcon mode={item.mode} />
							<span>{item.label}</span>
						</button>
					))}
				</div>
			</div>
			{projects.length > 0 ? (
				<div className="cal-chip-row">
					{projects.map((project) => {
						const selected = selectedProject === project;
						return (
							<button
								aria-pressed={selected}
								className="cal-chip"
								data-color={projectColorIndex(project, PALETTE_SIZE)}
								key={project}
								onClick={() =>
									setSelectedProject(selected ? undefined : project)
								}
								type="button"
							>
								<span className="cal-chip-dot" />
								{project}
							</button>
						);
					})}
				</div>
			) : null}
			{loading ? <p className="empty">Loading activity…</p> : null}
			{error !== undefined && !loading ? (
				<p className="error">{error}</p>
			) : null}
			{!loading && error === undefined && calendarSessions.length === 0 ? (
				<p className="empty">No activity recorded for this period.</p>
			) : null}
			{!loading && error === undefined && calendarSessions.length > 0 ? (
				<>
					<CalendarTimeline
						days={days}
						mode={mode}
						onSelect={setSelectedKey}
						selectedKey={selectedKey}
						sessions={calendarSessions}
					/>
					{selectedSession === undefined ? null : (
						<section className="cal-detail" aria-label="Selected activity">
							<strong>
								{selectedSession.project} / {selectedSession.task}
							</strong>
							<span>{timeRange(selectedSession)}</span>
							{selectedSession.planTitles.length > 0 ? (
								<ul>
									{selectedSession.planTitles.map((title) => (
										<li key={title}>{title}</li>
									))}
								</ul>
							) : null}
						</section>
					)}
				</>
			) : null}
		</div>
	);
}
