import { useEffect, useState } from "react";
import type { CompanionResolvedThemeMode } from "./themePreferences";

export function useSystemThemeMode(): CompanionResolvedThemeMode {
	const [systemThemeMode, setSystemThemeMode] =
		useState<CompanionResolvedThemeMode>("dark");

	useEffect(() => {
		const query = window.matchMedia("(prefers-color-scheme: light)");
		const applySystemTheme = () => {
			setSystemThemeMode(query.matches ? "light" : "dark");
		};
		applySystemTheme();
		query.addEventListener("change", applySystemTheme);
		return () => {
			query.removeEventListener("change", applySystemTheme);
		};
	}, []);

	return systemThemeMode;
}
