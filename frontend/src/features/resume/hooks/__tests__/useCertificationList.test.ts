import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { get: vi.fn() },
}));

import type { CertificationListResponse } from "@/features/resume";
import { useCertificationList } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

describe("useCertificationList", () => {
    const wrapper = createQueryWrapper();

    const mockCertificationList: CertificationListResponse = {
        names: [
            "基本情報技術者試験",
            "応用情報技術者試験",
            "データベーススペシャリスト試験",
            "AWS Certified Solutions Architect",
            "Oracle Certified Java Programmer",
        ],
    };

    beforeEach(() => {
        resetStoresAndMocks([]);
        vi.mocked(protectedApiClient.get).mockReset();
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
    });

    it("成功時はエラーストアをクリアし、データが取得されること", async () => {
        const mockResponse = { status: 200, data: mockCertificationList } as AxiosResponse<CertificationListResponse>;
        vi.mocked(protectedApiClient.get).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useCertificationList(), { wrapper });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalled();
        expect(result.current.data).toEqual(mockCertificationList);
    });
});
