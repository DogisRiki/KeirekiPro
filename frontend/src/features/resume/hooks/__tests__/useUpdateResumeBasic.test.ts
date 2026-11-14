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
        vi.spyOn(useResumeStore.getState(), "removeDirtyEntryId");
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
        expect(useResumeStore.getState().removeDirtyEntryId).toHaveBeenCalledWith(BASIC_INFO_ENTRY_ID);
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
        expect(useResumeStore.getState().removeDirtyEntryId).not.toHaveBeenCalled();
        expect(useNotificationStore.getState().setNotification).not.toHaveBeenCalled();
    });

    describe("ほかのエントリーの未保存", () => {
        const sentPayload = {
            resumeName: "更新後職務経歴書",
            date: "2024-01-15",
            lastName: "鈴木",
            firstName: "次郎",
        };

        it("基本情報を保存しても、ほかのエントリーが未保存なら未保存の変更が残ること", async () => {
            useResumeStore.getState().setResume(mockResume);
            useResumeStore.getState().updateResume(sentPayload);
            useResumeStore.getState().addDirtyEntryId("career-1");
            vi.mocked(protectedApiClient.put).mockResolvedValueOnce({ status: 200, data: mockResume });

            const { result } = renderHook(() => useUpdateResumeBasic("resume-1"), { wrapper });
            act(() => {
                result.current.mutate(sentPayload);
            });
            await waitFor(() => expect(result.current.isSuccess).toBe(true));

            const state = useResumeStore.getState();
            expect(state.dirtyEntryIds.has(BASIC_INFO_ENTRY_ID)).toBe(false);
            expect(state.isDirty).toBe(true);

            act(() => useResumeStore.getState().removeDirtyEntryId("career-1"));
            expect(useResumeStore.getState().isDirty).toBe(false);
        });
    });

    it("保存中に打った文字は、保存が終わったあとも欄に残り、未保存の変更として扱われること", async () => {
        useResumeStore.getState().setResume(mockResume);
        useResumeStore.getState().addDirtyEntryId(BASIC_INFO_ENTRY_ID);

        let resolveSave: (value: unknown) => void = () => undefined;
        vi.mocked(protectedApiClient.put).mockReturnValueOnce(
            new Promise((resolve) => {
                resolveSave = resolve;
            }),
        );

        const { result } = renderHook(() => useUpdateResumeBasic("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                resumeName: mockResume.resumeName,
                date: mockResume.date,
                lastName: mockResume.lastName ?? "",
                firstName: mockResume.firstName ?? "",
            });
        });
        await waitFor(() => expect(protectedApiClient.put).toHaveBeenCalled());

        // 保存が終わる前に別の欄へ文字を打つ
        act(() => {
            useResumeStore.getState().updateResume({ lastName: "保存中に打った文字" });
        });
        await act(async () => {
            resolveSave({ status: 200, data: { ...mockResume, updatedAt: "2024-02-10T00:00:00.000Z" } });
        });
        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        const { resume, dirtyEntryIds, isDirty } = useResumeStore.getState();
        expect(resume?.lastName).toBe("保存中に打った文字");
        expect(resume?.updatedAt).toBe("2024-02-10T00:00:00.000Z");
        expect(dirtyEntryIds.has(BASIC_INFO_ENTRY_ID)).toBe(true);
        expect(isDirty).toBe(true);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "基本情報を保存しました。",
            "success",
        );
    });
});
