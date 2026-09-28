import type { AxiosAdapter, AxiosResponse, InternalAxiosRequestConfig } from "axios";
import { AxiosError } from "axios";
import { vi } from "vitest";

import { toastMessage } from "@/config/messages";
import { paths } from "@/config/paths";
import { baseApiClient, protectedApiClient } from "@/lib";
import { useUserAuthStore } from "@/stores";
import { createAxiosResponse, resetStoresAndMocks } from "@/test";
import type { User } from "@/types";

/**
 * 実際の通信の代わりに、受け取ったリクエストを記録して決まった応答を返すアダプタ
 */
const createAdapter = (statuses: number[]) => {
    const requests: InternalAxiosRequestConfig[] = [];
    const adapter: AxiosAdapter = async (config) => {
        requests.push(config);
        const status = statuses[requests.length - 1] ?? 200;
        const response = createAxiosResponse({ ok: true }, { status, config }) as AxiosResponse;
        if (status >= 400) {
            throw new AxiosError("Request failed", "ERR_BAD_REQUEST", config, {}, response);
        }
        return response;
    };
    return { adapter, requests };
};

describe("protectedApiClient", () => {
    let replace: ReturnType<typeof vi.spyOn>;

    beforeEach(() => {
        resetStoresAndMocks([]);
        sessionStorage.clear();
        useUserAuthStore.setState({ user: { id: "user-1" } as User, isAuthenticated: true });
        replace = vi.spyOn(window.location, "replace").mockImplementation(() => {});
        vi.spyOn(document, "cookie", "get").mockReturnValue("");
    });

    it("Cookieを付けて送ること", async () => {
        const { adapter, requests } = createAdapter([200]);

        await protectedApiClient.get("/resumes", { adapter });

        expect(requests[0].withCredentials).toBe(true);
    });

    it("CookieにXSRF-TOKENがあるときは、復号した値をX-XSRF-TOKENに付けること", async () => {
        vi.spyOn(document, "cookie", "get").mockReturnValue("SESSION=abc; XSRF-TOKEN=token%2Fvalue; theme=dark");
        const { adapter, requests } = createAdapter([200]);

        await protectedApiClient.post("/resumes", {}, { adapter });

        expect(requests[0].headers["X-XSRF-TOKEN"]).toBe("token/value");
    });

    it("CookieにXSRF-TOKENが無いときは、名前の似たCookieがあってもX-XSRF-TOKENを付けないこと", async () => {
        vi.spyOn(document, "cookie", "get").mockReturnValue("SESSION=abc; XSRF-SESSION=other; theme=dark");
        const { adapter, requests } = createAdapter([200]);

        await protectedApiClient.post("/resumes", {}, { adapter });

        expect(requests[0].headers["X-XSRF-TOKEN"]).toBeUndefined();
    });

    it("401のときは、トークンを再取得してから同じリクエストを送り直すこと", async () => {
        const refresh = vi.spyOn(baseApiClient, "post").mockResolvedValue(createAxiosResponse(null));
        const { adapter, requests } = createAdapter([401, 200]);

        const response = await protectedApiClient.get("/resumes", { adapter });

        expect(response.status).toBe(200);
        expect(refresh).toHaveBeenCalledTimes(1);
        expect(refresh).toHaveBeenCalledWith("/auth/token/refresh", null, {
            withCredentials: true,
            skipAuthRefresh: true,
        });
        expect(requests).toHaveLength(2);
        expect(requests[1].url).toBe("/resumes");
        expect(useUserAuthStore.getState().isAuthenticated).toBe(true);
        expect(replace).not.toHaveBeenCalled();
        expect(sessionStorage.getItem("global-toast")).toBeNull();
    });

    it("トークンの再取得に失敗したときは、通知の内容をセッションに残し、ログアウトしてログイン画面へ移ること", async () => {
        vi.spyOn(baseApiClient, "post").mockRejectedValue(new Error("refresh token expired"));
        const { adapter, requests } = createAdapter([401]);

        await expect(protectedApiClient.get("/resumes", { adapter })).rejects.toThrow("refresh failed");

        expect(JSON.parse(sessionStorage.getItem("global-toast") ?? "null")).toEqual({
            m: toastMessage.unauthorized,
            t: "error",
        });
        expect(useUserAuthStore.getState().isAuthenticated).toBe(false);
        expect(useUserAuthStore.getState().user).toBeNull();
        expect(replace).toHaveBeenCalledWith(paths.login);
        expect(requests).toHaveLength(1);
    });

    it("401以外のエラーでは、トークンを再取得せず、共通のエラー処理に渡すこと", async () => {
        const refresh = vi.spyOn(baseApiClient, "post");
        const { adapter } = createAdapter([403]);

        await expect(protectedApiClient.get("/resumes", { adapter })).rejects.toBeInstanceOf(AxiosError);

        expect(refresh).not.toHaveBeenCalled();
        expect(useUserAuthStore.getState().isAuthenticated).toBe(false);
        expect(replace).toHaveBeenCalledWith(paths.top);
        expect(sessionStorage.getItem("global-toast")).toBeNull();
    });
});
