import type { ErrorResponse } from "@/types";
import { create } from "zustand";
import { devtools } from "zustand/middleware";
import { clearNotificationFromStoreCoordinator, registerErrorMessageStoreClear } from "./storeCoordinator";

interface ErrorMessageState {
    message: string | null;
    errors: {
        [field: string]: string[];
    };
    errorId: string | null;
    setErrors: (errorResponse: ErrorResponse) => void;
    clearErrors: () => void;
}

const createErrorId = (): string => {
    if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
        return crypto.randomUUID();
    }

    return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
};

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
                    clearNotificationFromStoreCoordinator();
                }
                set(
                    {
                        message: errorResponse.message,
                        errors: errorResponse.errors,
                        errorId: createErrorId(),
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

registerErrorMessageStoreClear(() => {
    useErrorMessageStore.getState().clearErrors();
});
