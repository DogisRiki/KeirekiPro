import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { put: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { BASIC_INFO_ENTRY_ID, useResumeStore, useUpdateResumeBasic } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import type { ErrorResponse } from "@/types";
import { act, renderHook, waitFor } from "@testing-library/react";

describe("useUpdateResumeBasic", () => {
    const wrapper = createQueryWrapper();

    const mockResume: Resume = {
        id: "resume-1",
        resumeName: "更新後職務経歴書",
        date: "2024-01-15",
        lastName: "鈴木",
        firstName: "次郎",
        createdAt: "2024-01-01T00:00:00.000Z",
        updatedAt: "2024-01-02T00:00:00.000Z",
        careers: [],
        projects: [],
        certifications: [],
        portfolios: [],
        snsPlatforms: [],
        selfPromotions: [],
    };

    beforeEach(() => {
        resetStoresAndMocks([]);
        useResumeStore.getState().clearResume();
        vi.mocked(protectedApiClient.put).mockReset();
        vi.spyOn(useNotificationStore.getState(), "setNotification");
        vi.spyOn(useResumeStore.getState(), "updateResumeFromServer");
        vi.spyOn(useResumeStore.getState(), "setDirty");
        vi.spyOn(useResumeStore.getState(), "setEntryErrors");
        vi.spyOn(useResumeStore.getState(), "clearEntryErrors");
    });

    it("成功時はエントリエラーをクリアし、ストア更新と成功通知が実行されること", async () => {
        const mockResponse = { status: 200, data: mockResume };
        vi.mocked(protectedApiClient.put).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useUpdateResumeBasic("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                resumeName: "更新後職務経歴書",
                date: "2024-01-15",
                lastName: "鈴木",
                firstName: "次郎",
            });
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenNthCalledWith(1, BASIC_INFO_ENTRY_ID);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenNthCalledWith(2, BASIC_INFO_ENTRY_ID);

        expect(useResumeStore.getState().updateResumeFromServer).toHaveBeenCalledWith({
            resumeName: mockResume.resumeName,
            date: mockResume.date,
            lastName: mockResume.lastName,
            firstName: mockResume.firstName,
            updatedAt: mockResume.updatedAt,
        });
        expect(useResumeStore.getState().setDirty).toHaveBeenCalledWith(false);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "基本情報を保存しました。",
            "success",
        );
    });

    it("失敗時はエラーレスポンスのerrorsが存在する場合に、該当エントリへエラーが設定されること", async () => {
        const mockErrorResponse: ErrorResponse = {
            message: "入力内容に誤りがあります",
            errors: {
                resumeName: ["入力してください。"],
            },
        };
        const mockError = {
            response: {
                data: mockErrorResponse,
            },
        };

        vi.mocked(protectedApiClient.put).mockRejectedValueOnce(mockError);

        const { result } = renderHook(() => useUpdateResumeBasic("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                resumeName: "",
                date: "2024-01-15",
                lastName: "鈴木",
                firstName: "次郎",
            });
        });

        await waitFor(() => expect(result.current.isError).toBe(true));

        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledTimes(1);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledWith(BASIC_INFO_ENTRY_ID);

        expect(useResumeStore.getState().setEntryErrors).toHaveBeenCalledWith(
            BASIC_INFO_ENTRY_ID,
            mockErrorResponse.errors,
        );

        expect(useResumeStore.getState().updateResumeFromServer).not.toHaveBeenCalled();
        expect(useResumeStore.getState().setDirty).not.toHaveBeenCalled();
        expect(useNotificationStore.getState().setNotification).not.toHaveBeenCalled();
    });
});
