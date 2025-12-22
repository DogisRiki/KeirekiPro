import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { TEMP_ID_PREFIX, useCreateSnsPlatform, useResumeStore } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import type { ErrorResponse } from "@/types";
import { act, renderHook, waitFor } from "@testing-library/react";

describe("useCreateSnsPlatform", () => {
    const wrapper = createQueryWrapper();

    const tempId = `${TEMP_ID_PREFIX}sns-platform-temp-1`;
    const localOnlyTempId = `${TEMP_ID_PREFIX}sns-platform-temp-2`;

    const localResume: Resume = {
        id: "resume-1",
        resumeName: "テスト職務経歴書",
        date: "2024-01-01",
        lastName: "山田",
        firstName: "太郎",
        createdAt: "2024-01-01T00:00:00.000Z",
        updatedAt: "2024-01-01T00:00:00.000Z",
        careers: [],
        projects: [],
        certifications: [],
        portfolios: [],
        snsPlatforms: [
            {
                id: tempId,
                name: "一時SNS",
                link: "https://example.com/temp",
            },
            {
                id: "sns-platform-1",
                name: "ローカル（dirty）SNS名",
                link: "https://example.com/local-dirty",
            },
            {
                id: localOnlyTempId,
                name: "ローカルのみ（temp）",
                link: "https://example.com/local-only-temp",
            },
        ],
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

    it("成功時はエントリエラーをクリアし、snsPlatformsをマージしてストア更新・activeEntryId更新・dirty解除・通知が実行されること", async () => {
        // store準備
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().setActiveSection("snsPlatform");
        useResumeStore.getState().setActiveEntryId(tempId);
        useResumeStore.getState().addDirtyEntryId(tempId);
        useResumeStore.getState().addDirtyEntryId("sns-platform-1"); // serverから返るIDをdirtyとして上書き対象にする

        const serverResume: Resume = {
            ...localResume,
            updatedAt: "2024-02-01T00:00:00.000Z",
            snsPlatforms: [
                {
                    id: "sns-platform-1",
                    name: "サーバーSNSプラットフォーム（上書きされる想定）",
                    link: "https://example.com/server-overwritten",
                },
                {
                    id: "sns-platform-2",
                    name: "新規作成されたSNSプラットフォーム",
                    link: "https://example.com/new",
                },
            ],
        };

        const mockResponse = { status: 201, data: serverResume };
        vi.mocked(protectedApiClient.post).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useCreateSnsPlatform("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                tempId,
                payload: {
                    name: "一時SNSプラットフォーム",
                    link: "https://example.com/temp",
                },
            });
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // snsPlatformsのマージ結果：
        // - 保存対象のtempIdは除外
        // - ローカルのみのエントリー（localOnlyTempId）を先頭へ
        // - server snsPlatformsをベースに、dirtyなsns-platform-1はローカルデータで上書き
        const expectedSnsPlatforms = [
            localResume.snsPlatforms.find((s) => s.id === localOnlyTempId)!,
            localResume.snsPlatforms.find((s) => s.id === "sns-platform-1")!, // dirtyなのでローカルが優先
            serverResume.snsPlatforms.find((s) => s.id === "sns-platform-2")!,
        ];

        // clearEntryErrorsはonMutateとonSuccessで計2回呼ばれる
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenNthCalledWith(1, tempId);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenNthCalledWith(2, tempId);

        expect(useResumeStore.getState().updateResumeFromServer).toHaveBeenCalledWith({
            snsPlatforms: expectedSnsPlatforms,
            updatedAt: serverResume.updatedAt,
        });
        expect(useResumeStore.getState().setActiveEntryId).toHaveBeenCalledWith("sns-platform-2");
        expect(useResumeStore.getState().removeDirtyEntryId).toHaveBeenCalledWith(tempId);
        expect(useResumeStore.getState().setDirty).toHaveBeenCalledWith(false);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith("SNSを作成しました。", "success");
    });

    it("失敗時はエラーレスポンスのerrorsが存在する場合に、該当エントリへエラーが設定されること", async () => {
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().setActiveSection("snsPlatform");
        useResumeStore.getState().setActiveEntryId(tempId);

        const mockErrorResponse: ErrorResponse = {
            message: "入力内容に誤りがあります",
            errors: {
                name: ["入力してください。"],
            },
        };
        const mockError = {
            response: {
                data: mockErrorResponse,
            },
        };

        vi.mocked(protectedApiClient.post).mockRejectedValueOnce(mockError);

        const { result } = renderHook(() => useCreateSnsPlatform("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                tempId,
                payload: {
                    name: "",
                    link: "https://example.com/temp",
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
