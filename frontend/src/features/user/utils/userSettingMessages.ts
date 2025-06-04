import { paths } from "@/config/paths";
import { SettingMessages, UserState } from "@/features/user";

/**
 * ユーザー状態と外部連携数から表示メッセージを生成する
 * @param state ユーザー情報
 * @param providerCount 外部認証連携数
 * @returns メッセージオブジェクト
 */
export const createUserSettingMessages = (state: UserState, providerCount: number): SettingMessages => {
    /**
     * メールアドレス + パスワード関連
     */
    const { emailPasswordStatusLabel, emailPasswordNavigationMessage, emailPasswordIsWarning, emailPasswordLinkPath } =
        (() => {
            switch (state) {
                // パスワード設定済み (外部連携なし)
                case UserState.EMAIL_PASSWORD:
                    return {
                        emailPasswordStatusLabel: "パスワード設定済み",
                        emailPasswordNavigationMessage: "パスワードの変更はこちら",
                        emailPasswordIsWarning: false,
                        emailPasswordLinkPath: paths.password.change,
                    };
                // すべて設定済み (メールアドレス + パスワード + 外部連携)
                case UserState.EMAIL_PASSWORD_WITH_PROVIDER:
                    return {
                        emailPasswordStatusLabel: "メールアドレス+パスワードは設定済み",
                        emailPasswordNavigationMessage: "パスワードの変更はこちら",
                        emailPasswordIsWarning: false,
                        emailPasswordLinkPath: paths.password.change,
                    };
                // パスワード未設定 (メールアドレス + 外部連携)
                case UserState.EMAIL_WITH_PROVIDER:
                    return {
                        emailPasswordStatusLabel: "パスワードが未設定",
                        emailPasswordNavigationMessage: "パスワードの設定はこちら",
                        emailPasswordIsWarning: true,
                        emailPasswordLinkPath: paths.emailPassword.set,
                    };
                // メールアドレス・パスワードとも未設定 (外部連携のみ)
                case UserState.PROVIDER_ONLY:
                    return {
                        emailPasswordStatusLabel: "メールアドレス+パスワードが未設定",
                        emailPasswordNavigationMessage: "パスワードとメールアドレスの設定はこちら",
                        emailPasswordIsWarning: true,
                        emailPasswordLinkPath: paths.emailPassword.set,
                    };
                // 型安全フォールバック
                default:
                    return {
                        emailPasswordStatusLabel: "",
                        emailPasswordNavigationMessage: "",
                        emailPasswordIsWarning: false,
                        emailPasswordLinkPath: paths.user,
                    };
            }
        })();

    /**
     * 外部連携解除関連
     */
    const providerMessage = (() => {
        if (providerCount > 1) return null;
        switch (state) {
            case UserState.EMAIL_WITH_PROVIDER:
                return "パスワードが未設定のため、連携を解除できません。";
            case UserState.PROVIDER_ONLY:
                return "メールアドレスとパスワードが未設定のため、連携を解除できません。";
            default:
                return null;
        }
    })();

    return {
        emailPasswordStatusLabel,
        emailPasswordNavigationMessage,
        emailPasswordIsWarning,
        emailPasswordLinkPath,
        providerMessage,
    };
};
