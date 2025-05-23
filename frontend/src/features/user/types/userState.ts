/**
 * ユーザー状態列挙型
 */
export enum UserState {
    /**
     * EMAIL_PASSWORD : メールアドレス + パスワードのみ設定済（外部認証なし）
     */
    EMAIL_PASSWORD = "EMAIL_PASSWORD",

    /**
     * EMAIL_WITH_PROVIDER : メールアドレスは設定済、パスワード未設定、外部認証あり
     */
    EMAIL_WITH_PROVIDER = "EMAIL_WITH_PROVIDER",

    /**
     * PROVIDER_ONLY : メールアドレス・パスワードは未設定、外部認証のみ
     */
    PROVIDER_ONLY = "PROVIDER_ONLY",

    /**
     * EMAIL_PASSWORD_WITH_PROVIDER : すべて設定済（メールアドレス + パスワード + 外部認証）
     */
    EMAIL_PASSWORD_WITH_PROVIDER = "EMAIL_PASSWORD_WITH_PROVIDER",

    /**
     * 未判定（ユーザー情報未取得・ログアウト直後など）
     */
    UNKNOWN = "UNKNOWN",
}

/**
 * 設定画面で表示するメッセージ
 */
export interface SettingMessages {
    /**
     * 設定状態ラベル
     */
    emailPasswordStatusLabel: string;

    /**
     * ナビゲーションメッセージ
     */
    emailPasswordNavigationMessage: string;

    /**
     * 警告表示判定
     */
    emailPasswordIsWarning: boolean;

    /**
     * ナビゲーションリンク
     */
    emailPasswordLinkPath: string;

    /**
     * 外部連携に関する警告メッセージ(なしの場合はnull)
     */
    providerMessage: string | null;
}
