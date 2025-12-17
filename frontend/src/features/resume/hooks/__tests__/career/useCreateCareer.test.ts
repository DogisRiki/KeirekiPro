import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { TEMP_ID_PREFIX, useCreateCareer, useResumeStore } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import type { ErrorResponse } from "@/types";
import { act, renderHook, waitFor } from "@testing-library/react";

describe("useCreateCareer", () => {
    const wrapper = createQueryWrapper();

    const tempId = `${TEMP_ID_PREFIX}career-temp-1`;
    const localOnlyTempId = `${TEMP_ID_PREFIX}career-temp-2`;

    const localResume: Resume = {
        id: "resume-1",
        resumeName: "テスト職務経歴書",
        date: "2024-01-01",
        lastName: "山田",
        firstName: "太郎",
        createdAt: "2024-01-01T00:00:00.000Z",
        updatedAt: "2024-01-01T00:00:00.000Z",
        careers: [
            {
                id: tempId,
                companyName: "一時職歴",
                startDate: "2024-01",
                endDate: null,
                active: true,
            },
            {
                id: "career-1",
                companyName: "ローカル（dirty）会社名",
                startDate: "2020-04",
                endDate: null,
                active: true,
            },
            {
                id: localOnlyTempId,
                companyName: "ローカルのみ（temp）",
                startDate: "2023-01",
                endDate: null,
                active: true,
            },
        ],
        projects: [],
        certifications: [],
        portfolios: [],
        socialLinks: [],
        selfPromotions: [],
    };

    beforeEach(() => {
        resetStoresAndMocks([]);
        useResumeStore.getState().clearResume();
        vi.mocked(protectedApiClient.post).mockReset();
        vi.spyOn(useNotificationStore.getState(), "setNotification");
        vi.spyOn(useResumeStore.getState(), "updateResumeFromServer");
        vi.spyOn(useResumeStore.getState(), "setDirty");
        vi.spyOn(useResumeStore.getState(), "removeDirtyEntryId");
        vi.spyOn(useResumeStore.getState(), "setActiveEntryId");
        vi.spyOn(useResumeStore.getState(), "setEntryErrors");
        vi.spyOn(useResumeStore.getState(), "clearEntryErrors");
    });

    it("成功時はエントリエラーをクリアし、careerをマージしてストア更新・activeEntryId更新・dirty解除・通知が実行されること", async () => {
        // store準備
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().setActiveSection("career");
        useResumeStore.getState().setActiveEntryId(tempId);
        useResumeStore.getState().addDirtyEntryId(tempId);
        useResumeStore.getState().addDirtyEntryId("career-1"); // serverから返るIDをdirtyとして上書き対象にする

        const serverResume: Resume = {
            ...localResume,
            updatedAt: "2024-02-01T00:00:00.000Z",
            careers: [
                {
                    id: "career-1",
                    companyName: "サーバー会社名（上書きされる想定）",
                    startDate: "2020-04",
                    endDate: null,
                    active: true,
                },
                {
                    id: "career-2",
                    companyName: "新規作成された職歴",
                    startDate: "2024-01",
                    endDate: null,
                    active: true,
                },
            ],
        };

        const mockResponse = { status: 201, data: serverResume };
        vi.mocked(protectedApiClient.post).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useCreateCareer("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                tempId,
                payload: {
                    companyName: "一時職歴",
                    startDate: "2024-01",
                    endDate: null,
                    isActive: true,
                },
            });
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // careerのマージ結果：
        // - 保存対象のtempIdは除外
        // - ローカルのみのエントリー（localOnlyTempId）を先頭へ
        // - server careersをベースに、dirtyなcareer-1はローカルデータで上書き
        const expectedCareers = [
            localResume.careers.find((c) => c.id === localOnlyTempId)!,
            localResume.careers.find((c) => c.id === "career-1")!, // dirtyなのでローカルが優先
            serverResume.careers.find((c) => c.id === "career-2")!,
        ];

        // clearEntryErrorsはonMutateとonSuccessで計2回呼ばれる
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenNthCalledWith(1, tempId);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenNthCalledWith(2, tempId);

        expect(useResumeStore.getState().updateResumeFromServer).toHaveBeenCalledWith({
            careers: expectedCareers,
            updatedAt: serverResume.updatedAt,
        });
        expect(useResumeStore.getState().setActiveEntryId).toHaveBeenCalledWith("career-2");
        expect(useResumeStore.getState().removeDirtyEntryId).toHaveBeenCalledWith(tempId);
        expect(useResumeStore.getState().setDirty).toHaveBeenCalledWith(false);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith("職歴を作成しました。", "success");
    });

    it("失敗時はエラーレスポンスのerrorsが存在する場合に、該当エントリへエラーが設定されること", async () => {
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().setActiveSection("career");
        useResumeStore.getState().setActiveEntryId(tempId);

        const mockErrorResponse: ErrorResponse = {
            message: "入力内容に誤りがあります",
            errors: {
                companyName: ["入力してください。"],
            },
        };
        const mockError = {
            response: {
                data: mockErrorResponse,
            },
        };

        vi.mocked(protectedApiClient.post).mockRejectedValueOnce(mockError);

        const { result } = renderHook(() => useCreateCareer("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                tempId,
                payload: {
                    companyName: "",
                    startDate: "2024-01",
                    endDate: null,
                    isActive: true,
                },
            });
        });

        await waitFor(() => expect(result.current.isError).toBe(true));

        // clearEntryErrorsはonMutateで1回呼ばれる
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledTimes(1);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledWith(tempId);

        expect(useResumeStore.getState().setEntryErrors).toHaveBeenCalledWith(tempId, mockErrorResponse.errors);

        expect(useResumeStore.getState().updateResumeFromServer).not.toHaveBeenCalled();
        expect(useResumeStore.getState().setDirty).not.toHaveBeenCalled();
        expect(useNotificationStore.getState().setNotification).not.toHaveBeenCalled();
    });
});
