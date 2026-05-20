import type { AxiosResponse } from "axios";
import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: {
        get: vi.fn(),
    },
}));

import { paths } from "@/config/paths";
import { protectedApiClient } from "@/lib";
import { ProtectedLoader, PublicLoader } from "@/routes/AppLoader";
import { useUserAuthStore } from "@/stores";
import { resetStoresAndMocks } from "@/test";
import type { User } from "@/types";

const user: User = {
    id: "user-1",
    email: "user@example.com",
    username: "test-user",
    profileImage: null,
    twoFactorAuthEnabled: false,
    hasPassword: true,
    authProviders: [],
    roles: [],
};

const expectRedirectResponse = async (loaderPromise: Promise<unknown>, location: string) => {
    let response: unknown;

    try {
        await loaderPromise;
    } catch (error) {
        response = error;
    }

    expect(response).toBeInstanceOf(Response);
    expect((response as Response).status).toBe(302);
    expect((response as Response).headers.get("Location")).toBe(location);
};

describe("route loaders", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
        vi.mocked(protectedApiClient.get).mockReset();
    });

    it("PublicLoaderは認証済みの場合に職務経歴書一覧へredirectすること", async () => {
        useUserAuthStore.getState().setLogin(user);

        await expectRedirectResponse(PublicLoader(), paths.resume.list);
    });

    it("ProtectedLoaderは未認証でcurrent userを取得できない場合にloginへredirectすること", async () => {
        vi.mocked(protectedApiClient.get).mockRejectedValueOnce(new Error("unauthorized"));

        await expectRedirectResponse(ProtectedLoader(), paths.login);
    });

    it("ProtectedLoaderはcurrent user取得後にstoreへ認証状態を反映すること", async () => {
        vi.mocked(protectedApiClient.get).mockResolvedValueOnce({ data: user } as AxiosResponse<User>);

        await expect(ProtectedLoader()).resolves.toBeNull();

        expect(protectedApiClient.get).toHaveBeenCalledWith("/users/me", { skipAuthRefresh: true });
        expect(useUserAuthStore.getState().user).toEqual(user);
        expect(useUserAuthStore.getState().isAuthenticated).toBe(true);
    });
});
