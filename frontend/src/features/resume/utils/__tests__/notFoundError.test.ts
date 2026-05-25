import { isResumeNotFoundError, isSectionNotFoundError, RESUME_NOT_FOUND_MESSAGE } from "@/features/resume";
import type { ErrorResponse } from "@/types";
import type { AxiosError } from "axios";

const axiosError = (status: number, message: string): AxiosError<ErrorResponse> =>
    ({
        isAxiosError: true,
        response: {
            status,
            data: {
                message,
                errors: {},
            },
        },
    }) as AxiosError<ErrorResponse>;

describe("notFoundError", () => {
    it("職務経歴書本体不存在404を判定できること", () => {
        const error = axiosError(404, RESUME_NOT_FOUND_MESSAGE);

        expect(isResumeNotFoundError(error)).toBe(true);
        expect(isSectionNotFoundError(error)).toBe(false);
    });

    it("セクション不存在404を判定できること", () => {
        const error = axiosError(404, "対象のプロジェクトが存在しません。");

        expect(isResumeNotFoundError(error)).toBe(false);
        expect(isSectionNotFoundError(error)).toBe(true);
    });

    it("404以外はリソース不存在として扱わないこと", () => {
        const error = axiosError(400, RESUME_NOT_FOUND_MESSAGE);

        expect(isResumeNotFoundError(error)).toBe(false);
        expect(isSectionNotFoundError(error)).toBe(false);
    });
});
