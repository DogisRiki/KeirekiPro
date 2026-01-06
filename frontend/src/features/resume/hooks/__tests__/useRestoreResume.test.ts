import { vi } from "vitest";

const mockNavigate = vi.hoisted(() => vi.fn());
vi.mock("react-router", () => ({
    useNavigate: () => mockNavigate,
}));

vi.mock("@/config/paths", () => ({
    paths: {
        resume: {
            edit: "/resumes/:id/edit",
        },
    },
}));

vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { useRestoreResume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

describe("useRestoreResume", () => {
    const wrapper = createQueryWrapper();

    const mockResume: Resume = {
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
        selfPromotions: [],
    };

    beforeEach(() => {
        resetStoresAndMocks([]);
        vi.mocked(protectedApiClient.post).mockReset();
        mockNavigate.mockReset();
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useNotificationStore.getState(), "setNotification");
    });

    it("リストアが成功した場合、clearErrors・通知・遷移が正しく行われること", async () => {
        const mockResponse = { status: 200, data: mockResume } as AxiosResponse<Resume>;
        vi.mocked(protectedApiClient.post).mockResolvedValueOnce(mockResponse);

        const file = new File(['{"id":"resume-1"}'], "resume_backup.json", { type: "application/json" });

        const { result } = renderHook(() => useRestoreResume(), { wrapper });

        act(() => {
            result.current.mutate(file);
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));
        expect(protectedApiClient.post).toHaveBeenCalledWith("/resumes/restore", { id: "resume-1" });

        // onMutateとonSuccessの両方で呼ばれる
        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalled();

        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "職務経歴書をリストアしました。",
            "success",
        );

        expect(mockNavigate).toHaveBeenCalledWith("/resumes/resume-1/edit");
    });

    it("リストアが失敗した場合、isErrorがtrueになり、通知・遷移が行われないこと", async () => {
        vi.mocked(protectedApiClient.post).mockRejectedValueOnce(new Error("Network Error"));

        const file = new File(['{"id":"resume-1"}'], "resume_backup.json", { type: "application/json" });

        const { result } = renderHook(() => useRestoreResume(), { wrapper });

        act(() => {
            result.current.mutate(file);
        });

        await waitFor(() => expect(result.current.isError).toBe(true));

        expect(useNotificationStore.getState().setNotification).not.toHaveBeenCalled();
        expect(mockNavigate).not.toHaveBeenCalled();
    });
});
