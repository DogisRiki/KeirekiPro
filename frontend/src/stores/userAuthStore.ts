import { User, UserPatch } from "@/types";
import { create } from "zustand";
import { createJSONStorage, devtools, persist } from "zustand/middleware";

interface UserAuthState {
    user: User | null;
    isAuthenticated: boolean;
    setLogin: (user: User) => void;
    setLogout: () => void;
    setRefresh: () => void;
    updateUserInfo: (patch: UserPatch) => void;
}

/**
 * ユーザー認証ストア
 */
export const useUserAuthStore = create<UserAuthState>()(
    devtools(
        persist(
            (set) => ({
                user: null,
                isAuthenticated: false,
                setLogin: (user) => set({ user, isAuthenticated: true }, false, "setLogin"),
                setLogout: () => set({ user: null, isAuthenticated: false }, false, "setLogout"),
                setRefresh: () => set({ isAuthenticated: true }, false, "setRefresh"),
                updateUserInfo: (patch) =>
                    set(
                        (state) => ({
                            user: state.user ? { ...state.user, ...patch } : null,
                        }),
                        false,
                        "updateUserInfo",
                    ),
            }),
            {
                name: "auth-storage",
                storage: createJSONStorage(() => localStorage),
            },
        ),
        { name: "UserAuthStore" },
    ),
);
