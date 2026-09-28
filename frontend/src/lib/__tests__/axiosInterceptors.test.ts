import type { AxiosResponse, InternalAxiosRequestConfig } from "axios";
import { AxiosError, AxiosHeaders } from "axios";
import { vi } from "vitest";

import { toastMessage } from "@/config/messages";
import { paths } from "@/config/paths";
import { createErrorInterceptor } from "@/lib";
import { useErrorMessageStore, useNotificationStore, useUserAuthStore } from "@/stores";
import { resetStoresAndMocks } from "@/test";
import type { ErrorResponse, User } from "@/types";

const config = { headers: new AxiosHeaders() } as InternalAxiosRequestConfig;

const errorResponse: ErrorResponse = {
    message: "入力内容に誤りがあります",
    errors: { email: ["メールアドレスの形式が無効です"] },
};

/**
 * 指定したステータスの応答を持つAxiosErrorを作る
 */
const createAxiosError = (status: number, data: unknown, headers: Record<string, string> = {}) => {
    const response = {
        data,
        status,
        statusText: "",
        headers,
        config,
    } as AxiosResponse;
    return new AxiosError("Request failed", "ERR_BAD_REQUEST", config, {}, response);
};

describe("createErrorInterceptor", () => {
    let assign: ReturnType<typeof vi.spyOn>;
    let replace: ReturnType<typeof vi.spyOn>;

    beforeEach(() => {
        resetStoresAndMocks([]);
        useErrorMessageStore.setState({ message: null, errors: {}, errorId: null });
        useUserAuthStore.setState({ user: { id: "user-1" } as User, isAuthenticated: true });
        assign = vi.spyOn(window.location, "assign").mockImplementation(() => {});
        replace = vi.spyOn(window.location, "replace").mockImplementation(() => {});
    });

    it("応答が無いときは、サーバーエラーの画面へ移り、エラーを返すこと", async () => {
        const error = new AxiosError("Network Error", "ERR_NETWORK", config, {});

        await expect(createErrorInterceptor()(error)).rejects.toBe(error);

        expect(assign).toHaveBeenCalledWith(paths.serverError);
        expect(replace).not.toHaveBeenCalled();
        expect(useNotificationStore.getState().isShow).toBe(false);
    });

    it.each([400, 404])("%iのときは、エラー内容をエラーメッセージのストアに入れ、エラーを返すこと", async (status) => {
        const error = createAxiosError(status, errorResponse, { "content-type": "application/json" });

        await expect(createErrorInterceptor()(error)).rejects.toBe(error);

        const state = useErrorMessageStore.getState();
        expect(state.message).toBe(errorResponse.message);
        expect(state.errors).toEqual(errorResponse.errors);
        expect(assign).not.toHaveBeenCalled();
        expect(replace).not.toHaveBeenCalled();
        expect(useUserAuthStore.getState().isAuthenticated).toBe(true);
    });

    it("400で本文が無いときは、エラーメッセージのストアを変えないこと", async () => {
        const error = createAxiosError(400, "");

        await expect(createErrorInterceptor()(error)).rejects.toBe(error);

        expect(useErrorMessageStore.getState().message).toBeNull();
        expect(useErrorMessageStore.getState().errorId).toBeNull();
    });

    it("JSONのエラーがBlobで返ったときは、読み取ってストアに入れ、応答の本文も読み取った内容に置き換えること", async () => {
        const blob = new Blob([JSON.stringify(errorResponse)], { type: "application/json" });
        const error = createAxiosError(400, blob, { "content-type": "application/json;charset=UTF-8" });

        await expect(createErrorInterceptor()(error)).rejects.toBe(error);

        expect(useErrorMessageStore.getState().message).toBe(errorResponse.message);
        expect(useErrorMessageStore.getState().errors).toEqual(errorResponse.errors);
        expect(error.response?.data).toEqual(errorResponse);
    });

    it("BlobがJSONとして読めないときは、ストアに入れず、応答の本文もそのままにすること", async () => {
        const blob = new Blob(["not json"], { type: "application/json" });
        const error = createAxiosError(404, blob, { "content-type": "application/json" });

        await expect(createErrorInterceptor()(error)).rejects.toBe(error);

        expect(useErrorMessageStore.getState().message).toBeNull();
        expect(useErrorMessageStore.getState().errorId).toBeNull();
        expect(error.response?.data).toBe(blob);
    });

    it("403のときは、ログアウトしてトップ画面へ移り、エラーを返すこと", async () => {
        const error = createAxiosError(403, errorResponse);

        await expect(createErrorInterceptor()(error)).rejects.toBe(error);

        expect(useUserAuthStore.getState().isAuthenticated).toBe(false);
        expect(useUserAuthStore.getState().user).toBeNull();
        expect(replace).toHaveBeenCalledWith(paths.top);
        expect(assign).not.toHaveBeenCalled();
        expect(useErrorMessageStore.getState().message).toBeNull();
    });

    it("500のときは、サーバーエラーの通知を出し、エラーを返すこと", async () => {
        const error = createAxiosError(500, errorResponse);

        await expect(createErrorInterceptor()(error)).rejects.toBe(error);

        const state = useNotificationStore.getState();
        expect(state.message).toBe(toastMessage.serverError);
        expect(state.type).toBe("error");
        expect(state.isShow).toBe(true);
        expect(assign).not.toHaveBeenCalled();
        expect(replace).not.toHaveBeenCalled();
        expect(useErrorMessageStore.getState().message).toBeNull();
    });

    it("503のときは、メンテナンス画面へ移り、エラーを返すこと", async () => {
        const error = createAxiosError(503, errorResponse);

        await expect(createErrorInterceptor()(error)).rejects.toBe(error);

        expect(assign).toHaveBeenCalledWith(paths.maintenance);
        expect(replace).not.toHaveBeenCalled();
        expect(useNotificationStore.getState().isShow).toBe(false);
        expect(useUserAuthStore.getState().isAuthenticated).toBe(true);
    });

    it("それ以外のステータスのときは、何もせずエラーを返すこと", async () => {
        const error = createAxiosError(409, errorResponse);

        await expect(createErrorInterceptor()(error)).rejects.toBe(error);

        expect(assign).not.toHaveBeenCalled();
        expect(replace).not.toHaveBeenCalled();
        expect(useErrorMessageStore.getState().message).toBeNull();
        expect(useNotificationStore.getState().isShow).toBe(false);
        expect(useUserAuthStore.getState().isAuthenticated).toBe(true);
    });

    it("Axios以外のエラーは、何もせずそのまま返すこと", async () => {
        const error = new Error("unexpected");

        await expect(createErrorInterceptor()(error)).rejects.toBe(error);

        expect(assign).not.toHaveBeenCalled();
        expect(replace).not.toHaveBeenCalled();
    });
});
