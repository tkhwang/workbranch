import { useEffect, useState } from "react";

const REFRESH_INTERVAL_MS = 60 * 1000;

function currentEpochSeconds(): number {
	return Math.floor(Date.now() / 1000);
}

export function useCurrentEpochSeconds(fixedNow?: number): number {
	const [currentNow, setCurrentNow] = useState(currentEpochSeconds);
	useEffect(() => {
		if (fixedNow !== undefined) return;
		const timer = window.setInterval(() => {
			setCurrentNow(currentEpochSeconds());
		}, REFRESH_INTERVAL_MS);
		return () => window.clearInterval(timer);
	}, [fixedNow]);
	return fixedNow ?? currentNow;
}
