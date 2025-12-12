import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn() },
}));
const mockedNavigate = vi.fn();
vi.mock("react-router", () => ({
    useNavigate: () => mockedNavigate,
}));

import { paths } from "@/config/paths";
import type { Resume } from "@/features/resume";
import { useCreateResume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

describe("useCreateResume", () => {
    const wrapper = createQueryWrapper();

    beforeEach(() => {
        resetStoresAndMocks([]);
        vi.mocked(protectedApiClient.post).mockReset();
        mockedNavigate.mockReset();
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useNotificationStore.getState(), "setNotification");
    });

    it("成功時はエラーストアをクリアし、成功通知とリダイレクトが実行されること", async () => {
        const mockResume: Resume = {
            id: "new-resume-1",
            resumeName: "新規職務経歴書",
            date: "2024-01-01",
            lastName: null,
            firstName: null,
            createdAt: "2024-01-01T00:00:00.000Z",
            updatedAt: "2024-01-01T00:00:00.000Z",
            careers: [],
            projects: [],
            certifications: [],
            portfolios: [],
            socialLinks: [],
            selfPromotions: [],
        };
        const mockResponse = { status: 201, data: mockResume } as AxiosResponse<Resume>;
        vi.mocked(protectedApiClient.post).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useCreateResume(), { wrapper });

        act(() => {
            result.current.mutate({ resumeName: "新規職務経歴書" });
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "職務経歴書を作成しました。",
            "success",
        );
        expect(mockedNavigate).toHaveBeenCalledWith(paths.resume.edit.replace(":id", "new-resume-1"), {
            replace: true,
        });
    });
});
