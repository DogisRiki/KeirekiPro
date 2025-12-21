import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { get: vi.fn() },
}));

import type { SnsPlatformListResponse } from "@/features/resume";
import { useSnsPlatformList } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

describe("useSnsPlatformList", () => {
    const wrapper = createQueryWrapper();

    const mockSnsPlatformList: SnsPlatformListResponse = {
        names: ["GitHub", "X（Twitter）", "LinkedIn", "Facebook", "Qiita", "Zenn", "note"],
    };

    beforeEach(() => {
        resetStoresAndMocks([]);
        vi.mocked(protectedApiClient.get).mockReset();
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
    });

    it("成功時はエラーストアをクリアし、データが取得されること", async () => {
        const mockResponse = { status: 200, data: mockSnsPlatformList } as AxiosResponse<SnsPlatformListResponse>;
        vi.mocked(protectedApiClient.get).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useSnsPlatformList(), { wrapper });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalled();
        expect(result.current.data).toEqual(mockSnsPlatformList);
    });
});
