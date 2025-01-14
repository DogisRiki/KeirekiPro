import { updateUserProfile, User } from "@/types";
import { create } from "zustand";
import { createJSONStorage, devtools, persist } from "zustand/middleware";

interface UserAuthState {
    user: User | null;
    isAuthenticated: boolean;
    setLogin: (user: User) => void;
    setLogout: () => void;
    updateProfile: (params: Partial<updateUserProfile>) => void;
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
                setLogin: (user) => set({ isAuthenticated: true, user }, false, "setLogin"),
                setLogout: () => set({ isAuthenticated: false, user: null }, false, "setLogout"),
                updateProfile: (params) =>
                    set(
                        (state) => ({
                            user: state.user ? { ...state.user, ...params } : null,
                        }),
                        false,
                        "updateProfile",
                    ),
            }),
            {
                name: "auth-storage",
                storage: createJSONStorage(() => localStorage),
            },
        ),
        {
            name: "UserAuthStore",
        },
    ),
);
