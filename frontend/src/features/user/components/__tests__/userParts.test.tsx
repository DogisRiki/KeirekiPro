import type { SettingMessages } from "@/features/user";
import { AuthProviderWarningMessage, PasswordStatusBox, ProfileImageField } from "@/features/user";
import { renderWithProviders, resetStoresAndMocks } from "@/test";
import { fireEvent, screen } from "@testing-library/react";
import { vi } from "vitest";

const baseMessages: SettingMessages = {
    emailPasswordStatusLabel: "メールアドレスとパスワードは設定済みです",
    emailPasswordNavigationMessage: "変更はこちらから行えます。",
    emailPasswordIsWarning: false,
    emailPasswordLinkPath: "/password/change",
    providerMessage: null,
};

/** ファイル選択の欄(画面に出ない input 要素。値が空の入力欄はこれだけ) */
const fileInput = () => screen.getByDisplayValue("");

describe("ProfileImageField", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
    });

    it("今のプロフィール画像を表示すること", () => {
        renderWithProviders(<ProfileImageField currentImage="https://example.com/me.png" onChange={vi.fn()} />);

        expect(screen.getByRole("img", { name: "プロフィール画像" })).toHaveAttribute(
            "src",
            "https://example.com/me.png",
        );
    });

    it("プロフィール画像が無いときは、既定の表示にすること", () => {
        renderWithProviders(<ProfileImageField currentImage={null} onChange={vi.fn()} />);

        expect(screen.queryByRole("img", { name: "プロフィール画像" })).not.toBeInTheDocument();
        expect(screen.getByTestId("PersonIcon")).toBeInTheDocument();
    });

    it("画像を読み込めなかったときは、既定の表示に切り替えること", () => {
        renderWithProviders(<ProfileImageField currentImage="https://example.com/broken.png" onChange={vi.fn()} />);

        fireEvent.error(screen.getByRole("img", { name: "プロフィール画像" }));

        expect(screen.queryByRole("img", { name: "プロフィール画像" })).not.toBeInTheDocument();
        expect(screen.getByTestId("PersonIcon")).toBeInTheDocument();
    });

    it("カメラのボタンを押すと、ファイルの選択を開くこと", async () => {
        const openDialog = vi.spyOn(HTMLInputElement.prototype, "click").mockImplementation(() => {});
        const { user } = renderWithProviders(<ProfileImageField currentImage={null} onChange={vi.fn()} />);

        await user.click(screen.getByRole("button"));

        expect(openDialog).toHaveBeenCalledTimes(1);
    });

    it("画像を選んだときは、そのファイルを呼び出し元に渡すこと", () => {
        const onChange = vi.fn();
        renderWithProviders(<ProfileImageField currentImage={null} onChange={onChange} />);
        const file = new File(["image"], "me.png", { type: "image/png" });

        fireEvent.change(fileInput(), { target: { files: [file] } });

        expect(onChange).toHaveBeenCalledWith(file);
    });

    it("ファイルを選ばずに閉じたときは、呼び出し元に渡さないこと", () => {
        const onChange = vi.fn();
        renderWithProviders(<ProfileImageField currentImage={null} onChange={onChange} />);

        fireEvent.change(fileInput(), { target: { files: [] } });

        expect(onChange).not.toHaveBeenCalled();
    });

    it("読み込めなかった後に画像を選び直すと、画像の表示に戻すこと", () => {
        renderWithProviders(<ProfileImageField currentImage="https://example.com/me.png" onChange={vi.fn()} />);
        fireEvent.error(screen.getByRole("img", { name: "プロフィール画像" }));

        fireEvent.change(fileInput(), {
            target: { files: [new File(["image"], "me.png", { type: "image/png" })] },
        });

        expect(screen.getByRole("img", { name: "プロフィール画像" })).toHaveAttribute(
            "src",
            "https://example.com/me.png",
        );
    });
});

describe("PasswordStatusBox", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
    });

    it("設定状態と、「こちら」を遷移先へのリンクにした案内を表示すること", () => {
        renderWithProviders(
            <PasswordStatusBox
                statusLabel="パスワードが未設定です"
                navigationMessage="設定はこちらから行えます。"
                isWarning
                linkPath="/email-password/set"
            />,
        );

        expect(screen.getByText("パスワードが未設定です")).toBeInTheDocument();
        expect(screen.getByRole("link", { name: "こちら" })).toHaveAttribute("href", "/email-password/set");
        expect(screen.getByText(/設定は/)).toHaveTextContent("設定はこちらから行えます。");
    });

    it("警告のときは、警告のアイコンを出すこと", () => {
        renderWithProviders(
            <PasswordStatusBox statusLabel="未設定" navigationMessage="こちら" isWarning linkPath="/" />,
        );

        expect(screen.getByTestId("CancelIcon")).toBeInTheDocument();
        expect(screen.queryByTestId("CheckCircleIcon")).not.toBeInTheDocument();
    });

    it("警告でないときは、設定済みのアイコンを出すこと", () => {
        renderWithProviders(
            <PasswordStatusBox statusLabel="設定済み" navigationMessage="こちら" isWarning={false} linkPath="/" />,
        );

        expect(screen.getByTestId("CheckCircleIcon")).toBeInTheDocument();
        expect(screen.queryByTestId("CancelIcon")).not.toBeInTheDocument();
    });
});

describe("AuthProviderWarningMessage", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
    });

    it("外部連携の警告があるときは、警告として表示すること", () => {
        renderWithProviders(
            <AuthProviderWarningMessage
                messages={{ ...baseMessages, providerMessage: "Googleとの連携を解除できません" }}
            />,
        );

        expect(screen.getByRole("alert")).toHaveTextContent("Googleとの連携を解除できません");
    });

    it.each([null, ""])("外部連携の警告が無い(%s)ときは、何も表示しないこと", (providerMessage) => {
        renderWithProviders(<AuthProviderWarningMessage messages={{ ...baseMessages, providerMessage }} />);

        expect(screen.queryByRole("alert")).not.toBeInTheDocument();
    });
});
