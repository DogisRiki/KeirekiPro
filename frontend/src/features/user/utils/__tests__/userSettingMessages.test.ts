import { paths } from "@/config/paths";
import { UserState, createUserSettingMessages } from "@/features/user";
import { describe, expect, it } from "vitest";

describe("createUserSettingMessages", () => {
    it("UserStateがEMAIL_PASSWORDのときに生成されるオブジェクトを検証", () => {
        const msgs = createUserSettingMessages(UserState.EMAIL_PASSWORD, 0, true);
        expect(msgs).toEqual({
            emailPasswordStatusLabel: "パスワード設定済み",
            emailPasswordNavigationMessage: "パスワードの変更はこちら",
            emailPasswordIsWarning: false,
            emailPasswordLinkPath: paths.password.change,
            providerMessage: null,
        });
    });

    it("EMAIL_PASSWORD_WITH_PROVIDERのときに生成されるオブジェクトを検証", () => {
        const msgs = createUserSettingMessages(UserState.EMAIL_PASSWORD_WITH_PROVIDER, 2, true);
        expect(msgs).toEqual({
            emailPasswordStatusLabel: "メールアドレス+パスワードは設定済み",
            emailPasswordNavigationMessage: "パスワードの変更はこちら",
            emailPasswordIsWarning: false,
            emailPasswordLinkPath: paths.password.change,
            providerMessage: null,
        });
    });

    it("EMAIL_WITH_PROVIDER + providerCount=1のときに生成されるオブジェクトを検証", () => {
        const msgs = createUserSettingMessages(UserState.EMAIL_WITH_PROVIDER, 1, true);
        expect(msgs).toEqual({
            emailPasswordStatusLabel: "パスワードが未設定",
            emailPasswordNavigationMessage: "パスワードの設定はこちら",
            emailPasswordIsWarning: true,
            emailPasswordLinkPath: paths.emailPassword.set,
            providerMessage: "パスワードが未設定のため、連携を解除できません。",
        });
    });

    it("PROVIDER_ONLY + providerCount=1のときに生成されるオブジェクトを検証", () => {
        const msgs = createUserSettingMessages(UserState.PROVIDER_ONLY, 1, true);
        expect(msgs).toEqual({
            emailPasswordStatusLabel: "メールアドレス+パスワードが未設定",
            emailPasswordNavigationMessage: "パスワードとメールアドレスの設定はこちら",
            emailPasswordIsWarning: true,
            emailPasswordLinkPath: paths.emailPassword.set,
            providerMessage: "メールアドレスとパスワードが未設定のため、連携を解除できません。",
        });
    });

    it("PASSWORD_WITH_PROVIDER ではメールアドレスとパスワードの設定の画面へのリンクを返す", () => {
        const msgs = createUserSettingMessages(UserState.PASSWORD_WITH_PROVIDER, 1, false);
        expect(msgs).toEqual({
            emailPasswordStatusLabel: "パスワードは設定済み、メールアドレスは確認待ち",
            emailPasswordNavigationMessage: "メールアドレスの設定はこちら",
            emailPasswordIsWarning: true,
            emailPasswordLinkPath: paths.emailPassword.set,
            providerMessage: "メールアドレスの確認が済んでいないため、連携を解除できません。",
        });
    });

    it("確認前のアカウントで外部連携が1つなら、メールアドレスの確認が済んでいないため連携を解除できないことを出す", () => {
        const msgs = createUserSettingMessages(UserState.EMAIL_PASSWORD_WITH_PROVIDER, 1, false);
        expect(msgs.providerMessage).toBe("メールアドレスの確認が済んでいないため、連携を解除できません。");
        // 確認済みのアカウントでは、外部連携が1つでも解除できるので文を出さない
        expect(createUserSettingMessages(UserState.EMAIL_PASSWORD_WITH_PROVIDER, 1, true).providerMessage).toBeNull();
        // 外部連携が2つ以上なら、確認前でも解除できるので文を出さない
        expect(createUserSettingMessages(UserState.EMAIL_PASSWORD_WITH_PROVIDER, 2, false).providerMessage).toBeNull();
    });

    it("UNKNOWNのとき、フォールバック用オブジェクトが生成されることを検証", () => {
        const msgs = createUserSettingMessages(UserState.UNKNOWN, 0, false);
        expect(msgs).toEqual({
            emailPasswordStatusLabel: "",
            emailPasswordNavigationMessage: "",
            emailPasswordIsWarning: false,
            emailPasswordLinkPath: paths.user,
            providerMessage: null,
        });
    });
});
