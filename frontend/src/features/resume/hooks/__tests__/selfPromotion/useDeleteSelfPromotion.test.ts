import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { get: vi.fn(), post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { useDeleteSelfPromotion, useResumeStore } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

describe("useDeleteSelfPromotion", () => {
    const wrapper = createQueryWrapper();

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
                title: "削除対象",
                content: "削除される本文",
            },
            {
                id: "self-promotion-2",
                title: "残る自己PR",
                content: "残る本文",
            },
        ],
    };

    beforeEach(() => {
        resetStoresAndMocks([]);
        useResumeStore.getState().clearResume();
        vi.mocked(protectedApiClient.delete).mockReset();
        vi.mocked(protectedApiClient.get).mockReset();

        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useNotificationStore.getState(), "setNotification");

        vi.spyOn(useResumeStore.getState(), "updateResume");
        vi.spyOn(useResumeStore.getState(), "setDirty");
        vi.spyOn(useResumeStore.getState(), "removeDirtyEntryId");
        vi.spyOn(useResumeStore.getState(), "setActiveEntryId");
    });

    it("成功時はエラーストアをクリアし、selfPromotion削除・dirty解除・通知が実行されること", async () => {
        const selfPromotionId = "self-promotion-1";

        // useDeleteSelfPromotionはuseResumeStore()を参照するため、render前に状態を入れておく
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().setActiveSection("selfPromotion");
        useResumeStore.getState().setActiveEntryId(selfPromotionId);
        useResumeStore.getState().addDirtyEntryId(selfPromotionId);

        const mockResponse = { status: 200, data: undefined } as AxiosResponse<void>;
        vi.mocked(protectedApiClient.delete).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useDeleteSelfPromotion("resume-1"), { wrapper });

        act(() => {
            result.current.mutate(selfPromotionId);
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().updateResume).toHaveBeenCalledWith({
            selfPromotions: [localResume.selfPromotions.find((s) => s.id === "self-promotion-2")!],
        });
        expect(useResumeStore.getState().removeDirtyEntryId).toHaveBeenCalledWith(selfPromotionId);
        expect(useResumeStore.getState().setActiveEntryId).toHaveBeenCalledWith(null);
        expect(useResumeStore.getState().setDirty).toHaveBeenCalledWith(false);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "自己PRを削除しました。",
            "success",
        );
    });

    it("自己PR不存在404の場合、空セクションが省略された詳細レスポンスでストアを同期すること", async () => {
        const selfPromotionId = "self-promotion-1";
        useResumeStore.getState().setResume({ ...localResume, selfPromotions: [localResume.selfPromotions[0]] });
        useResumeStore.getState().setActiveSection("selfPromotion");
        useResumeStore.getState().setActiveEntryId(selfPromotionId);

        vi.mocked(protectedApiClient.delete).mockRejectedValueOnce({
            isAxiosError: true,
            response: { status: 404, data: { message: "対象の自己PRが存在しません。", errors: {} } },
        });
        vi.mocked(protectedApiClient.get).mockResolvedValueOnce({
            data: {
                id: localResume.id,
                resumeName: localResume.resumeName,
                date: localResume.date,
                createdAt: localResume.createdAt,
                updatedAt: localResume.updatedAt,
            },
        } as unknown as AxiosResponse<Resume>);

        const { result } = renderHook(() => useDeleteSelfPromotion("resume-1"), { wrapper });

        act(() => result.current.mutate(selfPromotionId));

        await waitFor(() => expect(result.current.isError).toBe(true));
        await waitFor(() => expect(useResumeStore.getState().resume?.selfPromotions).toEqual([]));
        expect(protectedApiClient.get).toHaveBeenCalledWith("/resumes/resume-1");
        expect(useResumeStore.getState().activeEntryId).toBeNull();
    });
});
