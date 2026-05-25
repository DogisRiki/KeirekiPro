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
    });

    it("取得開始時に既存エラーを消去せず、データが取得されること", async () => {
        const mockResponse = { status: 200, data: mockSnsPlatformList } as AxiosResponse<SnsPlatformListResponse>;
        vi.mocked(protectedApiClient.get).mockResolvedValueOnce(mockResponse);
        useErrorMessageStore.getState().setErrors({ message: "維持するエラー", errors: {} });

        const { result } = renderHook(() => useSnsPlatformList(), { wrapper });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        expect(useErrorMessageStore.getState().message).toBe("維持するエラー");
        expect(result.current.data).toEqual(mockSnsPlatformList);
    });
});
