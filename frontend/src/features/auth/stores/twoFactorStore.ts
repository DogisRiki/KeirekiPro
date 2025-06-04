import { create } from "zustand";
import { devtools } from "zustand/middleware";

interface TwoFactorState {
    userId: string | null;
    setUserId: (id: string) => void;
    clear: () => void;
}

/**
 * 二段階認証に使用するユーザーIDを管理するストア
 */
export const useTwoFactorStore = create<TwoFactorState>()(
    devtools(
        (set) => ({
            userId: null,
            setUserId: (id) => set({ userId: id }, false, "setUserId"),
            clear: () => set({ userId: null }, false, "clear"),
        }),
        {
            name: "TwoFactorStore",
        },
    ),
);
