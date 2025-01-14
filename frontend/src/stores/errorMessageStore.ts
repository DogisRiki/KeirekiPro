import { ErrorResponse } from "@/types";
import { create } from "zustand";
import { devtools } from "zustand/middleware";

interface ErrorMessageState {
    message: string | null;
    errors: {
        [field: string]: string[];
    };
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
            setErrors: (errorResponse: ErrorResponse) =>
                set({ message: errorResponse.message, errors: errorResponse.errors }, false, "setErrors"),
            clearErrors: () => set({ message: null, errors: {} }, false, "clearErrors"),
        }),
        {
            name: "ErrorMessageStore",
        },
    ),
);
