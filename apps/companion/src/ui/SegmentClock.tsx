// A seven-segment HH:MM clock drawn in SVG, so it stays sharp at any size.

const SEGMENTS = ["a", "b", "c", "d", "e", "f", "g"] as const;
type Segment = (typeof SEGMENTS)[number];

const LIT: Readonly<Record<string, string>> = {
	"0": "abcdef",
	"1": "bc",
	"2": "abdeg",
	"3": "abcdg",
	"4": "bcfg",
	"5": "acdfg",
	"6": "acdefg",
	"7": "abc",
	"8": "abcdefg",
	"9": "abcdfg",
};

// In a 60×110 box: a top, b/c right, d bottom, e/f left, g middle.
const RECTS: Readonly<
	Record<Segment, { x: number; y: number; w: number; h: number }>
> = {
	a: { x: 12, y: 0, w: 36, h: 10 },
	b: { x: 50, y: 12, w: 10, h: 37 },
	c: { x: 50, y: 61, w: 10, h: 37 },
	d: { x: 12, y: 100, w: 36, h: 10 },
	e: { x: 0, y: 61, w: 10, h: 37 },
	f: { x: 0, y: 12, w: 10, h: 37 },
	g: { x: 12, y: 50, w: 36, h: 10 },
};

export function segmentsFor(digit: string): readonly Segment[] {
	const lit = LIT[digit] ?? "";
	return SEGMENTS.filter((segment) => lit.includes(segment));
}

function Digit({ digit }: { readonly digit: string }) {
	const lit = segmentsFor(digit);
	return (
		<svg aria-hidden="true" className="segment-digit" viewBox="0 0 60 110">
			{SEGMENTS.map((segment) => {
				const rect = RECTS[segment];
				return (
					<rect
						className="segment"
						data-on={lit.includes(segment) ? "true" : "false"}
						height={rect.h}
						key={segment}
						rx={5}
						width={rect.w}
						x={rect.x}
						y={rect.y}
					/>
				);
			})}
		</svg>
	);
}

function twoDigits(value: number): string {
	return String(value).padStart(2, "0");
}

export function SegmentClock({ now }: { readonly now: Date }) {
	const hours = twoDigits(now.getHours());
	const minutes = twoDigits(now.getMinutes());
	return (
		<div
			className="segment-clock"
			role="img"
			aria-label={`${hours}:${minutes}`}
		>
			<Digit digit={hours.charAt(0)} />
			<Digit digit={hours.charAt(1)} />
			<span
				aria-hidden="true"
				className="segment-colon"
				data-on={now.getSeconds() % 2 === 0 ? "true" : "false"}
			>
				<i />
				<i />
			</span>
			<Digit digit={minutes.charAt(0)} />
			<Digit digit={minutes.charAt(1)} />
		</div>
	);
}
