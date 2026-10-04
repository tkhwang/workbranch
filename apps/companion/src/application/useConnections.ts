import { useCallback, useEffect, useRef, useState } from "react";
import {
	inspectSetup,
	onSetupProgress,
	runSetupAction,
} from "../infrastructure/tauriClient";
import {
	createConnectionController,
	EMPTY_CONNECTION_STATE,
	type SetupAction,
} from "./connections";
export function useConnections(enabled: boolean) {
	const [state, setState] = useState(EMPTY_CONNECTION_STATE);
	const controller = useRef<ReturnType<typeof createConnectionController>>();
	useEffect(() => {
		if (!enabled) {
			setState({ ...EMPTY_CONNECTION_STATE, loading: false });
			return;
		}
		const next = createConnectionController(
			{
				inspect: inspectSetup,
				run: runSetupAction,
				subscribe: onSetupProgress,
				id: () => crypto.randomUUID(),
			},
			setState,
		);
		controller.current = next;
		void next.refresh();
		return () => {
			next.dispose();
			controller.current = undefined;
		};
	}, [enabled]);
	const refresh = useCallback(() => controller.current?.refresh(), []);
	const run = useCallback(
		(action: SetupAction) =>
			controller.current?.run(action) ?? Promise.resolve(false),
		[],
	);
	return { state, refresh, run };
}
