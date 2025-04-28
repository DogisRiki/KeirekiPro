package com.example.keirekipro.domain.model.user;

import java.util.Set;

import com.example.keirekipro.shared.Notification;

import lombok.EqualsAndHashCode;
import lombok.Getter;

/**
 * 外部認証連携
 */
@Getter
@EqualsAndHashCode
public class AuthProvider {

    /**
     * 外部プロバイダー一覧
     */
    private static final Set<String> PROVIDERS = Set.of("google", "github");

    /**
     * プロバイダー名
     */
    private final String providerName;

    /**
     * プロバイダー側ユーザーID
     */
    private final String providerUserId;

    /**
     * ファクトリーメソッド
     *
     * @param notification   通知オブジェクト
     * @param providerName   プロバイダー名
     * @param providerUserId プロバイダー側ユーザーID
     */
    public static AuthProvider create(
            Notification notification,
            String providerName,
            String providerUserId) {
        return new AuthProvider(notification, providerName, providerUserId);
    }

    private AuthProvider(
            Notification notification,
            String providerName,
            String providerUserId) {
        validate(notification, providerName, providerUserId);
        this.providerName = providerName == null ? null : providerName.toLowerCase();
        this.providerUserId = providerUserId;
    }

    private static void validate(
            Notification notification,
            String providerName,
            String providerUserId) {

        if (providerName == null || providerName.isBlank()) {
            notification.addError("providerName", "プロバイダータイプが空です。");
        } else if (!PROVIDERS.contains(providerName.toLowerCase())) {
            notification.addError("providerName", "許可されていないプロバイダー名です。");
        }
        if (providerUserId == null || providerUserId.isBlank()) {
            String message = String.format("%sでユーザーIDの取得に失敗しました。", providerName);
            notification.addError("providerUserId", message);
        }
    }
}
