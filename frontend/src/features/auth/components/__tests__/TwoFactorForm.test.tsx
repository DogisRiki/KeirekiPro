import { screen } from "@testing-library/react";
import { vi } from "vitest";

// 開発サーバと本番ビルドでは、react-verification-input の既定の書き出しが { default: 部品 } の形で届く。
// テストの実行環境はこの形を自動でほどくため、その形をそのまま再現して確かめる
vi.mock("react-verification-input", async () => {
    const actual = await vi.importActual<{ default: unknown }>("react-verification-input");
    return { default: { default: actual.default } };
});

import { TwoFactorForm } from "@/features/auth";
import { renderWithProviders, resetStoresAndMocks } from "@/test";

describe("TwoFactorForm", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
    });

    it("コード入力部品が包まれた形で届いても、コードを入力する欄を表示すること", async () => {
        const onCodeChange = vi.fn();
        const { user } = renderWithProviders(<TwoFactorForm code="" onCodeChange={onCodeChange} onSubmit={vi.fn()} />);

        await user.type(screen.getByRole("textbox"), "1");

        expect(onCodeChange).toHaveBeenCalledWith("1");
        expect(screen.getByRole("button", { name: "認証" })).toBeDisabled();
    });
});
