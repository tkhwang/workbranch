import { useCallback, useEffect, useRef, useState } from "react";
import {
	applyUpdates,
	checkUpdates,
	onUpdateProgress,
	relaunchCompanion,
} from "../infrastructure/tauriClient";
import { createUpdateController, EMPTY_UPDATE_STATE } from "./updates";

export function useUpdates(enabled: boolean, onUpdated: () => void) {
	const [state, setState] = useState(EMPTY_UPDATE_STATE);
	const controller = useRef<ReturnType<typeof createUpdateController>>();
	const onUpdatedRef = useRef(onUpdated);
	onUpdatedRef.current = onUpdated;
	useEffect(() => {
		if (!enabled) {
			setState(EMPTY_UPDATE_STATE);
			return;
		}
		const next = createUpdateController(
			{
				inspect: checkUpdates,
				apply: applyUpdates,
				subscribe: onUpdateProgress,
				relaunch: relaunchCompanion,
				id: () => crypto.randomUUID(),
				onUpdated: () => onUpdatedRef.current(),
			},
			setState,
		);
		controller.current = next;
		return () => {
			next.dispose();
			controller.current = undefined;
		};
	}, [enabled]);
	const check = useCallback(() => controller.current?.check(), []);
	const apply = useCallback(
		() => controller.current?.apply() ?? Promise.resolve(false),
		[],
	);
	return { state, check, apply };
}
