package com.example.keirekipro.domain.model.user;

/**
 * ロール種別
 */
public enum RoleName {

    /**
     * 一般ユーザー
     */
    USER,

    /**
     * 管理者
     */
    ADMIN;

    /**
     * デフォルトロールを返す
     *
     * @return デフォルトロール
     */
    public static RoleName defaultRole() {
        return USER;
    }
}
