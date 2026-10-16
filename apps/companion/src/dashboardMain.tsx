import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { DashboardApp } from "./DashboardApp";
import "./styles/base.css";
import "./styles/themes.css";
import "./styles/dashboard.css";

const root = document.getElementById("root");

if (root instanceof HTMLElement) {
	createRoot(root).render(
		<StrictMode>
			<DashboardApp />
		</StrictMode>,
	);
}
