import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { get: vi.fn(), post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { useDeleteCertification, useResumeStore } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

describe("useDeleteCertification", () => {
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
        certifications: [
            {
                id: "cert-1",
                name: "削除対象",
                date: "2020-06-01",
            },
            {
                id: "cert-2",
                name: "残る資格",
                date: "2021-01-01",
            },
        ],
        portfolios: [],
        snsPlatforms: [],
        selfPromotions: [],
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

    it("成功時はエラーストアをクリアし、certification削除・dirty解除・通知が実行されること", async () => {
        const certificationId = "cert-1";

        // useDeleteCertificationはuseResumeStore()を参照するため、render前に状態を入れておく
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().setActiveSection("certification");
        useResumeStore.getState().setActiveEntryId(certificationId);
        useResumeStore.getState().addDirtyEntryId(certificationId);

        const mockResponse = { status: 200, data: undefined } as AxiosResponse<void>;
        vi.mocked(protectedApiClient.delete).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useDeleteCertification("resume-1"), { wrapper });

        act(() => {
            result.current.mutate(certificationId);
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().updateResume).toHaveBeenCalledWith({
            certifications: [localResume.certifications.find((c) => c.id === "cert-2")!],
        });
        expect(useResumeStore.getState().removeDirtyEntryId).toHaveBeenCalledWith(certificationId);
        expect(useResumeStore.getState().setActiveEntryId).toHaveBeenCalledWith(null);
        expect(useResumeStore.getState().setDirty).toHaveBeenCalledWith(false);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith("資格を削除しました。", "success");
    });

    it("資格不存在404の場合、空セクションが省略された詳細レスポンスでストアを同期すること", async () => {
        const certificationId = "cert-1";
        const staleResume: Resume = {
            ...localResume,
            certifications: [localResume.certifications[0]],
        };
        const responseWithoutSections = {
            id: staleResume.id,
            resumeName: staleResume.resumeName,
            date: staleResume.date,
            lastName: staleResume.lastName,
            firstName: staleResume.firstName,
            createdAt: staleResume.createdAt,
            updatedAt: staleResume.updatedAt,
        };

        useResumeStore.getState().setResume(staleResume);
        useResumeStore.getState().setActiveSection("certification");
        useResumeStore.getState().setActiveEntryId(certificationId);

        vi.mocked(protectedApiClient.delete).mockRejectedValueOnce({
            isAxiosError: true,
            response: {
                status: 404,
                data: { message: "対象の資格が存在しません。", errors: {} },
            },
        });
        vi.mocked(protectedApiClient.get).mockResolvedValueOnce({
            data: responseWithoutSections,
        } as unknown as AxiosResponse<Resume>);

        const { result } = renderHook(() => useDeleteCertification("resume-1"), { wrapper });

        act(() => {
            result.current.mutate(certificationId);
        });

        await waitFor(() => expect(result.current.isError).toBe(true));
        await waitFor(() => expect(useResumeStore.getState().resume?.certifications).toEqual([]));

        expect(protectedApiClient.get).toHaveBeenCalledWith("/resumes/resume-1");
        expect(useResumeStore.getState().activeEntryId).toBeNull();
    });
});
