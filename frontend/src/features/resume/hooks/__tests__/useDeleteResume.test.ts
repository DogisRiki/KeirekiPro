import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { delete: vi.fn() },
}));
const mockRefetch = vi.fn();
vi.mock("@/features/resume/hooks/useGetResumeList", () => ({
    useGetResumeList: () => ({ refetch: mockRefetch }),
}));

import { useDeleteResume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

describe("useDeleteResume", () => {
    const wrapper = createQueryWrapper();

    beforeEach(() => {
        resetStoresAndMocks([]);
        vi.mocked(protectedApiClient.delete).mockReset();
        mockRefetch.mockReset();
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useNotificationStore.getState(), "setNotification");
    });

    it("成功時はエラーストアをクリアし、成功通知とrefetchが実行されること", async () => {
        const mockResponse = { status: 204, data: undefined } as AxiosResponse<void>;
        vi.mocked(protectedApiClient.delete).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useDeleteResume(), { wrapper });

        act(() => {
            result.current.mutate("resume-1");
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "職務経歴書を削除しました。",
            "success",
        );
        expect(mockRefetch).toHaveBeenCalled();
    });
});
