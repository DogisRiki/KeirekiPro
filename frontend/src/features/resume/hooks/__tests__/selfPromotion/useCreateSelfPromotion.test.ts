import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { TEMP_ID_PREFIX, useCreateSelfPromotion, useResumeStore } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

describe("useCreateSelfPromotion", () => {
    const wrapper = createQueryWrapper();

    const tempId = `${TEMP_ID_PREFIX}self-promotion-temp-1`;
    const localOnlyTempId = `${TEMP_ID_PREFIX}self-promotion-temp-2`;

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
        socialLinks: [],
        selfPromotions: [
            {
                id: tempId,
                title: "一時自己PR",
                content: "一時自己PR本文",
            },
            {
                id: "self-promotion-1",
                title: "ローカル（dirty）タイトル",
                content: "ローカル（dirty）本文",
            },
            {
                id: localOnlyTempId,
                title: "ローカルのみ（temp）タイトル",
                content: "ローカルのみ（temp）本文",
            },
        ],
    };

    beforeEach(() => {
        resetStoresAndMocks([]);
        useResumeStore.getState().clearResume();
        vi.mocked(protectedApiClient.post).mockReset();

        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useNotificationStore.getState(), "setNotification");

        vi.spyOn(useResumeStore.getState(), "updateResumeFromServer");
        vi.spyOn(useResumeStore.getState(), "setDirty");
        vi.spyOn(useResumeStore.getState(), "removeDirtyEntryId");
        vi.spyOn(useResumeStore.getState(), "setActiveEntryId");
    });

    it("成功時はselfPromotionsをマージしてupdateResumeFromServerが呼ばれ、activeEntryId更新・dirty解除・通知が実行されること", async () => {
        // store準備
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().setActiveSection("selfPromotion");
        useResumeStore.getState().setActiveEntryId(tempId);
        useResumeStore.getState().addDirtyEntryId(tempId);
        useResumeStore.getState().addDirtyEntryId("self-promotion-1"); // serverから返るIDをdirtyとして上書き対象にする

        const serverResume: Resume = {
            ...localResume,
            updatedAt: "2024-02-01T00:00:00.000Z",
            selfPromotions: [
                {
                    id: "self-promotion-1",
                    title: "サーバータイトル（上書きされる想定）",
                    content: "サーバー本文（上書きされる想定）",
                },
                {
                    id: "self-promotion-2",
                    title: "新規作成された自己PR",
                    content: "新規作成本文",
                },
            ],
        };

        const mockResponse = { status: 201, data: serverResume } as AxiosResponse<Resume>;
        vi.mocked(protectedApiClient.post).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useCreateSelfPromotion("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                tempId,
                payload: {
                    title: "一時自己PR",
                    content: "一時自己PR本文",
                },
            });
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // selfPromotionsのマージ結果：
        // - 保存対象のtempIdは除外
        // - ローカルのみのエントリー（localOnlyTempId）を先頭へ
        // - server selfPromotionsをベースに、dirtyなself-promotion-1はローカルデータで上書き
        const expectedSelfPromotions = [
            localResume.selfPromotions.find((s) => s.id === localOnlyTempId)!,
            localResume.selfPromotions.find((s) => s.id === "self-promotion-1")!, // dirtyなのでローカルが優先
            serverResume.selfPromotions.find((s) => s.id === "self-promotion-2")!,
        ];

        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().updateResumeFromServer).toHaveBeenCalledWith({
            selfPromotions: expectedSelfPromotions,
            updatedAt: serverResume.updatedAt,
        });
        expect(useResumeStore.getState().setActiveEntryId).toHaveBeenCalledWith("self-promotion-2");
        expect(useResumeStore.getState().removeDirtyEntryId).toHaveBeenCalledWith(tempId);
        expect(useResumeStore.getState().setDirty).toHaveBeenCalledWith(false);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "自己PRを作成しました。",
            "success",
        );
    });
});
