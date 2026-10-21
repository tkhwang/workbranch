// A seven-segment HH:MM clock drawn in SVG, so it stays sharp at any size.
// Classic display look: segments with pointed ends and gaps where they meet;
// dashboard.css slants the whole clock.

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

// In a 50×100 box, 9 thick with 1.5 gaps: a top, b/c right, d bottom,
// e/f left, g middle. Each segment is a hexagon pointed at both ends.
const POINTS: Readonly<Record<Segment, string>> = {
	a: "6,4.5 10.5,0 39.5,0 44,4.5 39.5,9 10.5,9",
	b: "45.5,6 50,10.5 50,44 45.5,48.5 41,44 41,10.5",
	c: "45.5,51.5 50,56 50,89.5 45.5,94 41,89.5 41,56",
	d: "6,95.5 10.5,91 39.5,91 44,95.5 39.5,100 10.5,100",
	e: "4.5,51.5 9,56 9,89.5 4.5,94 0,89.5 0,56",
	f: "4.5,6 9,10.5 9,44 4.5,48.5 0,44 0,10.5",
	g: "6,50 10.5,45.5 39.5,45.5 44,50 39.5,54.5 10.5,54.5",
};

export function segmentsFor(digit: string): readonly Segment[] {
	const lit = LIT[digit] ?? "";
	return SEGMENTS.filter((segment) => lit.includes(segment));
}

function Digit({ digit }: { readonly digit: string }) {
	const lit = segmentsFor(digit);
	return (
		<svg aria-hidden="true" className="segment-digit" viewBox="0 0 50 100">
			{SEGMENTS.map((segment) => (
				<polygon
					className="segment"
					data-on={lit.includes(segment) ? "true" : "false"}
					key={segment}
					points={POINTS[segment]}
				/>
			))}
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
