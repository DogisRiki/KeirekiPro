import { screen, waitFor } from "@testing-library/react";
import type { AxiosResponse, InternalAxiosRequestConfig } from "axios";
import { AxiosError, AxiosHeaders } from "axios";
import { vi } from "vitest";

import type * as Lib from "@/lib";

// 共通のエラーの受け口は本物を使い、通信だけを差し替える
vi.mock("@/lib", async (importOriginal) => {
    const actual = await importOriginal<typeof Lib>();
    return {
        ...actual,
        publicApiClient: { get: vi.fn(), post: vi.fn() },
    };
});

import { ErrorBanner } from "@/components/errors";
import { paths } from "@/config/paths";
import { LoginContainer } from "@/features/auth";
import { createErrorInterceptor, publicApiClient } from "@/lib";
import { useNotificationStore } from "@/stores";
import { renderWithProviders, resetStoresAndMocks } from "@/test";

const config = { headers: new AxiosHeaders() } as InternalAxiosRequestConfig;

const NOT_VERIFIED_MESSAGE = "メールアドレスの確認が済んでいません。";
const UNVERIFIED_EMAIL_MESSAGE =
    "このメールアドレスのアカウントがすでにあります。先にメールアドレスとパスワードでログインし、メールアドレスの確認を済ませてください。";

/**
 * 指定したステータスの応答で、共通のエラーの受け口を通して失敗させる
 */
const rejectWith = (status: number, data: unknown) => {
    const response = {
        data,
        status,
        statusText: "",
        headers: { "content-type": "application/json" },
        config,
    } as AxiosResponse;
    return createErrorInterceptor()(new AxiosError("Request failed", "ERR_BAD_REQUEST", config, {}, response));
};

const notVerifiedResponse = (kind: string) => ({
    message: NOT_VERIFIED_MESSAGE,
    errors: {},
    kind,
});

const renderLogin = (route: string = paths.login) =>
    renderWithProviders(
        <>
            <ErrorBanner />
            <LoginContainer />
        </>,
        { route },
    );

/**
 * メールアドレスとパスワードを入れてログインのボタンを押す
 */
const submitLogin = async (user: ReturnType<typeof renderLogin>["user"]) => {
    await user.type(screen.getByLabelText("メールアドレス"), "test@example.com");
    await user.type(screen.getByLabelText("パスワード"), "pass1234");
    await user.click(screen.getByRole("button", { name: "ログイン" }));
};

describe("LoginContainer", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
        vi.mocked(publicApiClient.post).mockReset();
        vi.spyOn(useNotificationStore.getState(), "setNotification");
    });

    it("409 の PENDING_REGISTRATION では確認がまだであることと送り直すボタンを出す", async () => {
        vi.mocked(publicApiClient.post).mockImplementationOnce(() =>
            rejectWith(409, notVerifiedResponse("PENDING_REGISTRATION")),
        );

        const { user } = renderLogin();
        await submitLogin(user);

        expect(await screen.findByText(NOT_VERIFIED_MESSAGE)).toBeInTheDocument();
        expect(screen.getByRole("button", { name: "確認のメールを送り直す" })).toBeInTheDocument();
        expect(screen.queryByRole("button", { name: "確認のメールを送る" })).not.toBeInTheDocument();
    });

    it("409 の UNVERIFIED_ACCOUNT_EMAIL では確認のメールを送るボタンを出し、押すと入力欄のメールアドレスとパスワードで送る", async () => {
        vi.mocked(publicApiClient.post)
            .mockImplementationOnce(() => rejectWith(409, notVerifiedResponse("UNVERIFIED_ACCOUNT_EMAIL")))
            .mockResolvedValueOnce({ status: 204, data: undefined } as AxiosResponse<void>);

        const { user } = renderLogin();
        await submitLogin(user);

        expect(await screen.findByText(NOT_VERIFIED_MESSAGE)).toBeInTheDocument();
        expect(screen.queryByRole("button", { name: "確認のメールを送り直す" })).not.toBeInTheDocument();

        await user.click(screen.getByRole("button", { name: "確認のメールを送る" }));

        await waitFor(() =>
            expect(publicApiClient.post).toHaveBeenCalledWith("/auth/email-verification/resend-for-login", {
                email: "test@example.com",
                password: "pass1234",
            }),
        );
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "確認のメールを送りました。メールの中の確認のリンクを押してください。",
            "success",
        );
    });

    it("400 では今と同じ文を出し、確認がまだであることを出さない", async () => {
        vi.mocked(publicApiClient.post).mockImplementationOnce(() =>
            rejectWith(400, { message: "メールアドレスまたはパスワードが正しくありません。", errors: {} }),
        );

        const { user } = renderLogin();
        await submitLogin(user);

        expect(await screen.findByText("メールアドレスまたはパスワードが正しくありません。")).toBeInTheDocument();
        expect(screen.queryByText(NOT_VERIFIED_MESSAGE)).not.toBeInTheDocument();
        expect(screen.queryByRole("button", { name: "確認のメールを送り直す" })).not.toBeInTheDocument();
        expect(screen.queryByRole("button", { name: "確認のメールを送る" })).not.toBeInTheDocument();
    });

    it("409 でも kind が分からない値のときは確認がまだであることを出さない", async () => {
        vi.mocked(publicApiClient.post).mockImplementationOnce(() => rejectWith(409, notVerifiedResponse("UNKNOWN")));

        const { user } = renderLogin();
        await submitLogin(user);

        await waitFor(() => expect(screen.getByRole("button", { name: "ログイン" })).toBeEnabled());
        expect(screen.queryByText(NOT_VERIFIED_MESSAGE)).not.toBeInTheDocument();
    });

    it("error=unverified_email のときだけ決まった案内の文を出す", () => {
        const { unmount } = renderLogin(`${paths.login}?error=unverified_email`);

        expect(screen.getByText(UNVERIFIED_EMAIL_MESSAGE)).toBeInTheDocument();

        unmount();
        renderLogin(`${paths.login}?error=${encodeURIComponent("偽の案内の文")}`);

        expect(screen.queryByText(UNVERIFIED_EMAIL_MESSAGE)).not.toBeInTheDocument();
        expect(screen.queryByText(/偽の案内の文/)).not.toBeInTheDocument();
    });

    it("1分たつ前に送ったときの 400 の文を ErrorBanner が出す", async () => {
        const rateLimitedMessage = "確認のメールは1分に1回まで送れます。少し待ってからもう一度お試しください。";
        vi.mocked(publicApiClient.post)
            .mockImplementationOnce(() => rejectWith(409, notVerifiedResponse("PENDING_REGISTRATION")))
            .mockImplementationOnce(() => rejectWith(400, { message: rateLimitedMessage, errors: {} }));

        const { user } = renderLogin();
        await submitLogin(user);

        await user.click(await screen.findByRole("button", { name: "確認のメールを送り直す" }));

        expect(await screen.findByText(rateLimitedMessage)).toBeInTheDocument();
        expect(useNotificationStore.getState().setNotification).not.toHaveBeenCalled();
    });
});
