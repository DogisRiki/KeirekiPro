import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { TEMP_ID_PREFIX, useResumeStore, useUpdateCareer } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import type { ErrorResponse } from "@/types";
import { act, renderHook, waitFor } from "@testing-library/react";

describe("useUpdateCareer", () => {
    const wrapper = createQueryWrapper();

    const localOnlyTempId = `${TEMP_ID_PREFIX}career-temp-99`;

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
                id: "career-1",
                companyName: "ローカル（更新対象・dirty）",
                startDate: "2020-04",
                endDate: null,
                active: true,
            },
            {
                id: "career-3",
                companyName: "ローカル（別dirty）",
                startDate: "2021-01",
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
        vi.spyOn(useResumeStore.getState(), "removeDirtyEntryId");
        vi.spyOn(useResumeStore.getState(), "setEntryErrors");
        vi.spyOn(useResumeStore.getState(), "clearEntryErrors");
    });

    it("成功時はエントリエラーをクリアし、careerをマージしてストア更新・dirty解除・通知が実行されること", async () => {
        const careerId = "career-1";

        // store準備
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().addDirtyEntryId(careerId);
        useResumeStore.getState().addDirtyEntryId("career-3");
        useResumeStore.getState().addDirtyEntryId(localOnlyTempId);

        const serverResume: Resume = {
            ...localResume,
            updatedAt: "2024-02-10T00:00:00.000Z",
            careers: [
                {
                    id: "career-1",
                    companyName: "サーバー（更新後）",
                    startDate: "2020-04",
                    endDate: null,
                    active: true,
                },
                {
                    id: "career-2",
                    companyName: "サーバー（別エントリー）",
                    startDate: "2019-01",
                    endDate: "2020-03",
                    active: false,
                },
                {
                    id: "career-3",
                    companyName: "サーバー（dirtyで上書きされる想定）",
                    startDate: "2021-01",
                    endDate: null,
                    active: true,
                },
            ],
        };

        const mockResponse = { status: 200, data: serverResume };
        vi.mocked(protectedApiClient.put).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useUpdateCareer("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                careerId,
                payload: {
                    companyName: "ローカル（更新対象・dirty）",
                    startDate: "2020-04",
                    endDate: null,
                    isActive: true,
                },
            });
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // マージ結果：
        // - ローカルのみのエントリー（temp）は先頭へ
        // - server careersをベースにdirtyな career-3はローカルデータで上書き
        // - 更新対象（careerId=career-1）はローカル上書き対象から除外されるため、serverが優先
        const expectedCareers = [
            localResume.careers.find((c) => c.id === localOnlyTempId)!,
            serverResume.careers.find((c) => c.id === "career-1")!, // server優先
            serverResume.careers.find((c) => c.id === "career-2")!,
            localResume.careers.find((c) => c.id === "career-3")!, // dirtyなのでローカル優先
        ];

        // clearEntryErrorsはonMutateとonSuccessで計2回呼ばれる
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenNthCalledWith(1, careerId);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenNthCalledWith(2, careerId);

        expect(useResumeStore.getState().updateResumeFromServer).toHaveBeenCalledWith({
            careers: expectedCareers,
            updatedAt: serverResume.updatedAt,
        });
        expect(useResumeStore.getState().removeDirtyEntryId).toHaveBeenCalledWith(careerId);
        expect(useResumeStore.getState().setDirty).toHaveBeenCalledWith(false);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith("職歴を更新しました。", "success");
    });

    it("失敗時はエラーレスポンスのerrorsが存在する場合に、該当エントリへエラーが設定されること", async () => {
        const careerId = "career-1";

        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().addDirtyEntryId(careerId);

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

        vi.mocked(protectedApiClient.put).mockRejectedValueOnce(mockError);

        const { result } = renderHook(() => useUpdateCareer("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                careerId,
                payload: {
                    companyName: "",
                    startDate: "2020-04",
                    endDate: null,
                    isActive: true,
                },
            });
        });

        await waitFor(() => expect(result.current.isError).toBe(true));

        // clearEntryErrorsはonMutateで1回呼ばれる
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledTimes(1);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledWith(careerId);

        expect(useResumeStore.getState().setEntryErrors).toHaveBeenCalledWith(careerId, mockErrorResponse.errors);

        expect(useResumeStore.getState().updateResumeFromServer).not.toHaveBeenCalled();
        expect(useResumeStore.getState().setDirty).not.toHaveBeenCalled();
        expect(useNotificationStore.getState().setNotification).not.toHaveBeenCalled();
    });
});
