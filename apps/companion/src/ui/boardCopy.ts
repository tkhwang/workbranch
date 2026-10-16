// Copy the menu bar board and the full-screen dashboard share, so both name
// a column, a wait reason or a turn's end the same way.

export const COLUMN_COPY = {
	waiting: { label: "내 응답 대기", code: "WAITING" },
	running: { label: "실행 중", code: "RUNNING" },
	finished: { label: "턴 종료 · 검토", code: "REVIEW" },
} as const satisfies Record<
	"waiting" | "running" | "finished",
	{ label: string; code: string }
>;

export const WAIT_REASON_LABELS: Readonly<Record<string, string>> = {
	permission: "권한 승인 대기",
	question: "질문 대기",
	plan: "plan 승인 대기",
	elicitation: "입력 대기",
};

/** How a finished turn ended, when it did not end normally. */
export const OUTCOME_LABELS = {
	interrupted: "중단됨",
	error: "오류로 종료",
} as const satisfies Record<"interrupted" | "error", string>;
