import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { get: vi.fn() },
}));

import type { GetResumeListResponse } from "@/features/resume";
import { useGetResumeList } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

describe("useGetResumeList", () => {
    const wrapper = createQueryWrapper();

    const mockResumeList: GetResumeListResponse = {
        resumes: [
            {
                id: "resume-1",
                resumeName: "職務経歴書1",
                createdAt: "2024-01-01T00:00:00.000Z",
                updatedAt: "2024-01-01T00:00:00.000Z",
            },
        ],
    };

    beforeEach(() => {
        resetStoresAndMocks([]);
        vi.mocked(protectedApiClient.get).mockReset();
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
    });

    it("成功時はエラーストアをクリアし、データが取得されること", async () => {
        const mockResponse = { status: 200, data: mockResumeList } as AxiosResponse<GetResumeListResponse>;
        vi.mocked(protectedApiClient.get).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useGetResumeList(), { wrapper });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalled();
        expect(result.current.data).toEqual(mockResumeList);
    });
});
