package com.example.keirekipro.domain.model.user;

import java.time.LocalDateTime;
import java.util.Set;
import java.util.UUID;

import com.example.keirekipro.domain.shared.Entity;
import com.example.keirekipro.shared.Notification;

import lombok.Getter;

/**
 * 外部認証連携エンティティ
 */
@Getter
public class AuthProvider extends Entity {

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
     * 作成日時
     */
    private final LocalDateTime createdAt;

    /**
     * 更新日時
     */
    private final LocalDateTime updatedAt;

    /**
     * プライベートコンストラクタ
     */
    private AuthProvider(
            UUID id,
            String providerName,
            String providerUserId,
            LocalDateTime createdAt,
            LocalDateTime updatedAt) {

        super(id, 1);
        this.providerName = providerName == null ? null : providerName.toLowerCase();
        this.providerUserId = providerUserId;
        this.createdAt = createdAt;
        this.updatedAt = updatedAt;
    }

    /**
     * 新規構築用ファクトリーメソッド
     *
     * @param notification   通知オブジェクト
     * @param providerName   プロバイダー名
     * @param providerUserId プロバイダー側ユーザーID
     * @return AuthProviderエンティティ
     */
    public static AuthProvider create(
            Notification notification,
            String providerName,
            String providerUserId) {

        validate(notification, providerName, providerUserId);

        return new AuthProvider(
                UUID.randomUUID(),
                providerName,
                providerUserId,
                LocalDateTime.now(),
                LocalDateTime.now());
    }

    /**
     *
     * @param id             識別子
     * @param providerName   プロバイダー名
     * @param providerUserId プロバイダー側ユーザーID
     * @param createdAt      作成日時
     * @param updatedAt      更新日時
     * @return AuthProviderエンティティ
     */
    public static AuthProvider reconstruct(
            UUID id,
            String providerName,
            String providerUserId,
            LocalDateTime createdAt,
            LocalDateTime updatedAt) {

        return new AuthProvider(id, providerName, providerUserId, createdAt, updatedAt);
    }

    private static void validate(
            Notification notification,
            String providerName,
            String providerUserId) {

        if (providerName == null || providerName.isBlank()) {
            notification.addError("providerName", "プロバイダー名が空です。");
        } else if (!PROVIDERS.contains(providerName.toLowerCase())) {
            notification.addError("providerName", "許可されていないプロバイダー名です。");
        }
        if (providerUserId == null || providerUserId.isBlank()) {
            String message = String.format("%sでユーザーIDの取得に失敗しました。", providerName);
            notification.addError("providerUserId", message);
        }
    }
}
