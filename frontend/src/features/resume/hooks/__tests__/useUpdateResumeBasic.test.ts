import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { put: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { useResumeStore, useUpdateResumeBasic } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

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
        socialLinks: [],
        selfPromotions: [],
    };

    beforeEach(() => {
        resetStoresAndMocks([]);
        useResumeStore.getState().clearResume();
        vi.mocked(protectedApiClient.put).mockReset();
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useNotificationStore.getState(), "setNotification");
        vi.spyOn(useResumeStore.getState(), "updateResume");
        vi.spyOn(useResumeStore.getState(), "setDirty");
    });

    it("成功時はエラーストアをクリアし、ストア更新と成功通知が実行されること", async () => {
        const mockResponse = { status: 200, data: mockResume } as AxiosResponse<Resume>;
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

        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().updateResume).toHaveBeenCalledWith({
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
});
