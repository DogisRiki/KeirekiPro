import { paths } from "@/config/paths";
import { UserState, createUserSettingMessages } from "@/features/user";
import { describe, expect, it } from "vitest";

describe("createUserSettingMessages", () => {
    it("UserStateがEMAIL_PASSWORDのときに生成されるオブジェクトを検証", () => {
        const msgs = createUserSettingMessages(UserState.EMAIL_PASSWORD, 0);
        expect(msgs).toEqual({
            emailPasswordStatusLabel: "パスワード設定済み",
            emailPasswordNavigationMessage: "パスワードの変更はこちら",
            emailPasswordIsWarning: false,
            emailPasswordLinkPath: paths.password.change,
            providerMessage: null,
        });
    });

    it("EMAIL_PASSWORD_WITH_PROVIDERのときに生成されるオブジェクトを検証", () => {
        const msgs = createUserSettingMessages(UserState.EMAIL_PASSWORD_WITH_PROVIDER, 2);
        expect(msgs).toEqual({
            emailPasswordStatusLabel: "メールアドレス+パスワードは設定済み",
            emailPasswordNavigationMessage: "パスワードの変更はこちら",
            emailPasswordIsWarning: false,
            emailPasswordLinkPath: paths.password.change,
            providerMessage: null,
        });
    });

    it("EMAIL_WITH_PROVIDER + providerCount=1のときに生成されるオブジェクトを検証", () => {
        const msgs = createUserSettingMessages(UserState.EMAIL_WITH_PROVIDER, 1);
        expect(msgs).toEqual({
            emailPasswordStatusLabel: "パスワードが未設定",
            emailPasswordNavigationMessage: "パスワードの設定はこちら",
            emailPasswordIsWarning: true,
            emailPasswordLinkPath: paths.emailPassword.set,
            providerMessage: "パスワードが未設定のため、連携を解除できません。",
        });
    });

    it("PROVIDER_ONLY + providerCount=1のときに生成されるオブジェクトを検証", () => {
        const msgs = createUserSettingMessages(UserState.PROVIDER_ONLY, 1);
        expect(msgs).toEqual({
            emailPasswordStatusLabel: "メールアドレス+パスワードが未設定",
            emailPasswordNavigationMessage: "パスワードとメールアドレスの設定はこちら",
            emailPasswordIsWarning: true,
            emailPasswordLinkPath: paths.emailPassword.set,
            providerMessage: "メールアドレスとパスワードが未設定のため、連携を解除できません。",
        });
    });

    it("UNKNOWNのとき、フォールバック用オブジェクトが生成されることを検証", () => {
        const msgs = createUserSettingMessages(UserState.UNKNOWN, 0);
        expect(msgs).toEqual({
            emailPasswordStatusLabel: "",
            emailPasswordNavigationMessage: "",
            emailPasswordIsWarning: false,
            emailPasswordLinkPath: paths.user,
            providerMessage: null,
        });
    });
});
