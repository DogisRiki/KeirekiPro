import { create } from "zustand";
import { createJSONStorage, devtools, persist } from "zustand/middleware";

interface ThemeState {
    mode: "light" | "dark";
    toggleMode: () => void;
}

/**
 * カラーモードを管理するストア
 */
export const useThemeStore = create<ThemeState>()(
    devtools(
        persist(
            (set) => ({
                mode: "light",
                toggleMode: () =>
                    set((state) => ({ mode: state.mode === "light" ? "dark" : "light" }), false, "toggleMode"),
            }),
            {
                name: "theme-storage",
                storage: createJSONStorage(() => localStorage),
            },
        ),
        { name: "ThemeStore" },
    ),
);
