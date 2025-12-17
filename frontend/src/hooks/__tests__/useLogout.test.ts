import { vi } from "vitest";

// モックをセット
vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn() },
}));

const mockedNavigate = vi.fn();
vi.mock("react-router", () => ({
    useNavigate: () => mockedNavigate,
}));

import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

import { paths } from "@/config/paths";
import { useLogout } from "@/hooks";
import { protectedApiClient } from "@/lib";
import { useUserAuthStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";

describe("useLogout", () => {
    const wrapper = createQueryWrapper();

    beforeEach(() => {
        // Zustandストアとモック関数をリセット
        resetStoresAndMocks([]);
        vi.mocked(protectedApiClient.post).mockReset();
        mockedNavigate.mockReset();
        // setLogoutをスパイ
        vi.spyOn(useUserAuthStore.getState(), "setLogout");
    });

    it("成功時はストアがクリアされ、画面遷移が実行されること", async () => {
        // protectedApiClient.postの成功レスポンスをセット
        const mockResponse = { status: 204, data: undefined } as AxiosResponse<void>;
        vi.mocked(protectedApiClient.post).mockResolvedValueOnce(mockResponse);

        // フックをレンダリング
        const { result } = renderHook(() => useLogout(), { wrapper });

        // ミューテート実行
        act(() => {
            result.current.mutate();
        });

        // 成功状態になるまで待機
        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // protectedApiClient.postが呼び出されること
        expect(protectedApiClient.post).toHaveBeenCalledWith("/auth/logout");

        // setLogoutが呼び出されること
        expect(useUserAuthStore.getState().setLogout).toHaveBeenCalled();

        // navigateが正しい引数で呼び出されること
        expect(mockedNavigate).toHaveBeenCalledWith(paths.login, { replace: true });
    });
});
