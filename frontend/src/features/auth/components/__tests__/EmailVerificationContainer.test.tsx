import { screen, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";
import { useState } from "react";
import { Route, Routes } from "react-router";
import { vi } from "vitest";

vi.mock("@/lib", () => ({
    publicApiClient: {
        post: vi.fn(),
    },
}));

import { paths } from "@/config/paths";
import type { EmailVerificationResult, VerifyEmailResponse } from "@/features/auth";
import { EmailVerificationContainer } from "@/features/auth";
import { publicApiClient } from "@/lib";
import { useNotificationStore } from "@/stores";
import { createAxiosResponse, renderWithProviders, resetStoresAndMocks } from "@/test";

const TOKEN = "verification-token";

/** 確認の API の応答を1回分だけ決める */
const mockVerifyResult = (result: EmailVerificationResult, passwordResetToken: string | null = null) => {
    vi.mocked(publicApiClient.post).mockResolvedValueOnce(
        createAxiosResponse<VerifyEmailResponse>({ result, passwordResetToken }),
    );
};

/** 確認のリンクの画面を、トークンを付けた URL で出す */
const renderVerifyEmail = (route = `${paths.email.verify}#${TOKEN}`) =>
    renderWithProviders(
        <Routes>
            <Route path={paths.email.verify} element={<EmailVerificationContainer />} />
            <Route path={paths.login} element={<div>login destination</div>} />
        </Routes>,
        { route },
    );

/** 押すたびに、確認のリンクの画面を作り直す親の部品 */
const RemountingParent = () => {
    const [count, setCount] = useState(0);
    return (
        <>
            <button type="button" onClick={() => setCount((c) => c + 1)}>
                出し直す
            </button>
            <EmailVerificationContainer key={count} />
        </>
    );
};

describe("EmailVerificationContainer", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
        vi.mocked(publicApiClient.post).mockReset();
    });

    afterEach(() => {
        window.history.replaceState(null, "", "/");
    });

    it("VERIFIED では確認が済んだこととログインの画面へ進むボタンを出す", async () => {
        mockVerifyResult("VERIFIED");

        const { user } = renderVerifyEmail();

        expect(
            await screen.findByText("メールアドレスの確認が済み、手続きが完了しました。ログインしてください。"),
        ).toBeInTheDocument();
        expect(publicApiClient.post).toHaveBeenCalledWith("/auth/email-verification/verify", { token: TOKEN });

        await user.click(screen.getByRole("button", { name: "ログイン画面へ" }));

        expect(await screen.findByText("login destination")).toBeInTheDocument();
    });

    it("PASSWORD_RESET_READY ではパスワードの再設定の入力欄を出し、再設定のトークンで送る", async () => {
        mockVerifyResult("PASSWORD_RESET_READY", "reset-token");
        vi.mocked(publicApiClient.post).mockResolvedValueOnce({ data: undefined } as AxiosResponse<void>);

        const { user } = renderVerifyEmail();

        expect(
            await screen.findByText("メールアドレスの確認が済みました。続けて新しいパスワードを設定してください。"),
        ).toBeInTheDocument();
        await user.type(screen.getByPlaceholderText("新しいパスワード"), "new-pass123");
        await user.type(screen.getByPlaceholderText("新しいパスワード(確認)"), "new-pass123");
        await user.click(screen.getByRole("button", { name: "パスワードを変更" }));

        expect(await screen.findByText("login destination")).toBeInTheDocument();
        expect(publicApiClient.post).toHaveBeenNthCalledWith(2, "/auth/password/reset", {
            token: "reset-token",
            password: "new-pass123",
            confirmPassword: "new-pass123",
        });
    });

    it("ALREADY_VERIFIED では確認がすでに済んだことを出す", async () => {
        mockVerifyResult("ALREADY_VERIFIED");

        renderVerifyEmail();

        expect(
            await screen.findByText("メールアドレスの確認はすでに済んでいます。ログインしてください。"),
        ).toBeInTheDocument();
        expect(screen.getByRole("button", { name: "ログイン画面へ" })).toBeInTheDocument();
    });

    it("EXPIRED では送り直すボタンを出し、押すとトークンで送り直す", async () => {
        mockVerifyResult("EXPIRED");
        vi.mocked(publicApiClient.post).mockResolvedValueOnce({ status: 204, data: undefined } as AxiosResponse<void>);

        const { user } = renderVerifyEmail();

        expect(
            await screen.findByText("このリンクは使えなくなっています。確認のメールを送り直してください。"),
        ).toBeInTheDocument();

        await user.click(screen.getByRole("button", { name: "確認のメールを送り直す" }));

        await waitFor(() =>
            expect(publicApiClient.post).toHaveBeenNthCalledWith(2, "/auth/email-verification/resend", {
                token: TOKEN,
            }),
        );
        await waitFor(() =>
            expect(useNotificationStore.getState().message).toBe(
                "確認のメールを送り直しました。メールの中の確認のリンクを押してください。",
            ),
        );
    });

    it("REGISTRATION_GONE では登録し直す案内と登録の画面へのリンクを出す", async () => {
        mockVerifyResult("REGISTRATION_GONE");

        renderVerifyEmail();

        expect(
            await screen.findByText("このリンクは使えなくなっています。お手数ですが、もう一度登録してください。"),
        ).toBeInTheDocument();
        expect(screen.getByRole("link", { name: "登録の画面へ" })).toHaveAttribute("href", paths.register);
        expect(screen.queryByRole("button", { name: "確認のメールを送り直す" })).not.toBeInTheDocument();
    });

    it("EMAIL_TAKEN ではこのメールアドレスは使えないことを出す", async () => {
        mockVerifyResult("EMAIL_TAKEN");

        renderVerifyEmail();

        expect(
            await screen.findByText("このメールアドレスは、すでにほかのアカウントが使っているため、使えません。"),
        ).toBeInTheDocument();
    });

    it("INVALID ではリンクが正しくないことを出す", async () => {
        mockVerifyResult("INVALID");

        renderVerifyEmail();

        expect(await screen.findByText("このリンクは正しくありません。")).toBeInTheDocument();
    });

    it("確認の API が失敗したときは、リンクが正しくないことを出す", async () => {
        vi.mocked(publicApiClient.post).mockRejectedValueOnce(new Error("failed"));

        renderVerifyEmail();

        expect(await screen.findByText("このリンクは正しくありません。")).toBeInTheDocument();
    });

    it("URL にトークンが無いときは、確認の API を呼ばずに、リンクが正しくないことを出す", () => {
        renderVerifyEmail(paths.email.verify);

        expect(screen.getByText("このリンクは正しくありません。")).toBeInTheDocument();
        expect(publicApiClient.post).not.toHaveBeenCalled();
    });

    it("トークンを読んだあと、URL から # 以降を消す", async () => {
        window.history.replaceState(null, "", `${paths.email.verify}?from=mail#${TOKEN}`);
        mockVerifyResult("VERIFIED");

        renderVerifyEmail();

        await screen.findByText("メールアドレスの確認が済み、手続きが完了しました。ログインしてください。");
        expect(window.location.hash).toBe("");
        expect(window.location.pathname).toBe(paths.email.verify);
        expect(window.location.search).toBe("?from=mail");
    });

    it("出し直しても、確認の API を2回呼ばない", async () => {
        mockVerifyResult("VERIFIED");

        const { user } = renderWithProviders(<RemountingParent />, { route: `${paths.email.verify}#${TOKEN}` });

        await screen.findByText("メールアドレスの確認が済み、手続きが完了しました。ログインしてください。");
        await user.click(screen.getByRole("button", { name: "出し直す" }));

        expect(
            screen.getByText("メールアドレスの確認が済み、手続きが完了しました。ログインしてください。"),
        ).toBeInTheDocument();
        expect(publicApiClient.post).toHaveBeenCalledTimes(1);
    });
});
