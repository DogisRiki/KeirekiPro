import { create } from "zustand";
import { devtools } from "zustand/middleware";

interface NotificationState {
    message: string | null;
    type: "success" | "error" | undefined;
    isShow: boolean;
    setNotification: (message: string, type: "success" | "error") => void;
    clearNotification: () => void;
}

/**
 * 処理結果の通知を管理するストア
 */
export const useNotificationStore = create<NotificationState>()(
    devtools((set) => ({
        message: null,
        type: undefined,
        isShow: false,
        setNotification: (message, type) => set({ message, type, isShow: true }),
        clearNotification: () => set({ message: null, type: undefined, isShow: false }),
    })),
);
