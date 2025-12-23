import type { ErrorResponse } from "@/types";
import { create } from "zustand";
import { devtools } from "zustand/middleware";

interface ErrorMessageState {
    message: string | null;
    errors: {
        [field: string]: string[];
    };
    errorId: string | null;
    setErrors: (errorResponse: ErrorResponse) => void;
    clearErrors: () => void;
}

/**
 * エラーメッセージを管理するストア
 */
export const useErrorMessageStore = create<ErrorMessageState>()(
    devtools(
        (set) => ({
            message: null,
            errors: {},
            errorId: null,
            setErrors: (errorResponse: ErrorResponse) => {
                // テスト環境以外でNotificationストアをクリア
                if (import.meta.env.MODE !== "test") {
                    import("@/stores/notificationStore").then(({ useNotificationStore }) => {
                        useNotificationStore.getState().clearNotification();
                    });
                }
                set(
                    {
                        message: errorResponse.message,
                        errors: errorResponse.errors,
                        errorId: crypto.randomUUID(),
                    },
                    false,
                    "setErrors",
                );
            },
            clearErrors: () => set({ message: null, errors: {}, errorId: null }, false, "clearErrors"),
        }),
        {
            name: "ErrorMessageStore",
        },
    ),
);
