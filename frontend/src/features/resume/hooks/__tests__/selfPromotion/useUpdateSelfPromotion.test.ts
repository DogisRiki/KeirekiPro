import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { TEMP_ID_PREFIX, useResumeStore, useUpdateSelfPromotion } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import type { ErrorResponse } from "@/types";
import { act, renderHook, waitFor } from "@testing-library/react";

describe("useUpdateSelfPromotion", () => {
    const wrapper = createQueryWrapper();

    const localOnlyTempId = `${TEMP_ID_PREFIX}self-promotion-temp-99`;

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
        snsPlatforms: [],
        selfPromotions: [
            {
                id: "self-promotion-1",
                title: "ローカル（更新対象・dirty）",
                content: "ローカル本文1（dirty）",
            },
            {
                id: "self-promotion-3",
                title: "ローカル（別dirty）",
                content: "ローカル本文3（dirty）",
            },
            {
                id: localOnlyTempId,
                title: "ローカルのみ（temp）",
                content: "ローカルのみ本文（temp）",
            },
        ],
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

    it("成功時はエントリエラーをクリアし、selfPromotionsをマージしてストア更新・dirty解除・通知が実行されること", async () => {
        const selfPromotionId = "self-promotion-1";

        // store準備
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().addDirtyEntryId(selfPromotionId);
        useResumeStore.getState().addDirtyEntryId("self-promotion-3");
        useResumeStore.getState().addDirtyEntryId(localOnlyTempId);

        const serverResume: Resume = {
            ...localResume,
            updatedAt: "2024-02-10T00:00:00.000Z",
            selfPromotions: [
                {
                    id: "self-promotion-1",
                    title: "サーバー（更新後）",
                    content: "サーバー本文1（更新後）",
                },
                {
                    id: "self-promotion-2",
                    title: "サーバー（別エントリー）",
                    content: "サーバー本文2",
                },
                {
                    id: "self-promotion-3",
                    title: "サーバー（dirtyで上書きされる想定）",
                    content: "サーバー本文3（上書きされる想定）",
                },
            ],
        };

        const mockResponse = { status: 200, data: serverResume };
        vi.mocked(protectedApiClient.put).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useUpdateSelfPromotion("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                selfPromotionId,
                payload: {
                    title: localResume.selfPromotions.find((s) => s.id === selfPromotionId)!.title,
                    content: localResume.selfPromotions.find((s) => s.id === selfPromotionId)!.content,
                },
            });
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // マージ結果：
        // - ローカルのみのエントリー（temp）は先頭へ
        // - server selfPromotionsをベースにdirtyな self-promotion-3はローカルデータで上書き
        // - 更新対象（selfPromotionId=self-promotion-1）はローカル上書き対象から除外されるため、serverが優先
        const expectedSelfPromotions = [
            localResume.selfPromotions.find((s) => s.id === localOnlyTempId)!,
            serverResume.selfPromotions.find((s) => s.id === "self-promotion-1")!, // server優先
            serverResume.selfPromotions.find((s) => s.id === "self-promotion-2")!,
            localResume.selfPromotions.find((s) => s.id === "self-promotion-3")!, // dirtyなのでローカル優先
        ];

        // clearEntryErrorsはonMutateとonSuccessで計2回呼ばれる
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenNthCalledWith(1, selfPromotionId);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenNthCalledWith(2, selfPromotionId);

        expect(useResumeStore.getState().updateResumeFromServer).toHaveBeenCalledWith({
            selfPromotions: expectedSelfPromotions,
            updatedAt: serverResume.updatedAt,
        });
        expect(useResumeStore.getState().removeDirtyEntryId).toHaveBeenCalledWith(selfPromotionId);
        expect(useResumeStore.getState().setDirty).toHaveBeenCalledWith(false);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "自己PRを更新しました。",
            "success",
        );
    });

    it("失敗時はエラーレスポンスのerrorsが存在する場合に、該当エントリへエラーが設定されること", async () => {
        const selfPromotionId = "self-promotion-1";

        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().addDirtyEntryId(selfPromotionId);

        const mockErrorResponse: ErrorResponse = {
            message: "入力内容に誤りがあります",
            errors: {
                title: ["入力してください。"],
            },
        };
        const mockError = {
            response: {
                data: mockErrorResponse,
            },
        };

        vi.mocked(protectedApiClient.put).mockRejectedValueOnce(mockError);

        const { result } = renderHook(() => useUpdateSelfPromotion("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                selfPromotionId,
                payload: {
                    title: "",
                    content: localResume.selfPromotions.find((s) => s.id === selfPromotionId)!.content,
                },
            });
        });

        await waitFor(() => expect(result.current.isError).toBe(true));

        // clearEntryErrorsはonMutateで1回呼ばれる
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledTimes(1);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledWith(selfPromotionId);

        expect(useResumeStore.getState().setEntryErrors).toHaveBeenCalledWith(
            selfPromotionId,
            mockErrorResponse.errors,
        );

        expect(useResumeStore.getState().updateResumeFromServer).not.toHaveBeenCalled();
        expect(useResumeStore.getState().setDirty).not.toHaveBeenCalled();
        expect(useNotificationStore.getState().setNotification).not.toHaveBeenCalled();
    });
});
