package com.example.keirekipro.domain.model.user;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import com.example.keirekipro.domain.event.user.UserDeletedEvent;
import com.example.keirekipro.domain.shared.Entity;
import com.example.keirekipro.domain.shared.event.DomainEvent;
import com.example.keirekipro.domain.shared.exception.DomainException;
import com.example.keirekipro.shared.Notification;

import lombok.Getter;

/**
 * ユーザー (ルートエンティティ)
 */
@Getter
public class User extends Entity {

    /**
     * メールアドレス
     */
    private final Email email;

    /**
     * パスワードハッシュ
     */
    private final String passwordHash;

    /**
     * 二段階認証設定
     */
    private final boolean twoFactorAuthEnabled;

    /**
     * 外部認証連携情報
     */
    private final Map<String, AuthProvider> authProviders;

    /**
     * プロフィール画像URL
     */
    private final String profileImage;

    /**
     * ユーザー名
     */
    private final String username;

    /**
     * 作成日時
     */
    private final LocalDateTime createdAt;

    /**
     * 更新日時
     */
    private final LocalDateTime updatedAt;

    /**
     * ドメインイベント蓄積用
     */
    private final List<DomainEvent> domainEvents = new ArrayList<>();

    /**
     * 新規構築用のコンストラクタ
     */
    private User(Notification notification,
            int orderNo,
            Email email,
            String passwordHash,
            boolean twoFactorAuthEnabled,
            Map<String, AuthProvider> authProviders,
            String profileImage,
            String username) {
        super(orderNo);

        // バリデーション実行
        validate(notification, email, passwordHash, authProviders);

        // サブエンティティや値オブジェクトのドメイン例外を一括でスローする
        if (notification.hasErrors()) {
            throw new DomainException(notification.getErrors());
        }

        this.email = email;
        this.passwordHash = passwordHash;
        this.twoFactorAuthEnabled = twoFactorAuthEnabled;
        this.authProviders = authProviders;
        this.profileImage = profileImage;
        this.username = username;
        this.createdAt = LocalDateTime.now();
        this.updatedAt = LocalDateTime.now();
    }

    /**
     * 再構築用のコンストラクタ
     */
    private User(UUID id,
            int orderNo,
            Email email,
            String passwordHash,
            boolean twoFactorAuthEnabled,
            Map<String, AuthProvider> authProviders,
            String profileImage,
            String username,
            LocalDateTime createdAt,
            LocalDateTime updatedAt) {
        super(id, orderNo);
        this.email = email;
        this.passwordHash = passwordHash;
        this.twoFactorAuthEnabled = twoFactorAuthEnabled;
        this.authProviders = authProviders;
        this.profileImage = profileImage;
        this.username = username;
        this.createdAt = createdAt;
        this.updatedAt = updatedAt;
    }

    /**
     * 新規構築用のファクトリーメソッド
     *
     * @param notification         通知オブジェクト
     * @param orderNo              並び順
     * @param email                メールアドレス
     * @param passwordHash         パスワードハッシュ
     * @param twoFactorAuthEnabled 二段階認証設定
     * @param authProviders        外部認証連携情報
     * @param profileImageUrl      プロフィール画像
     * @param username             ユーザー名
     * @return Userエンティティ
     */
    public static User create(Notification notification,
            int orderNo,
            Email email,
            String passwordHash,
            boolean twoFactorAuthEnabled,
            Map<String, AuthProvider> authProviders,
            String profileImageUrl,
            String username) {

        if (authProviders == null || authProviders.isEmpty()) {
            authProviders = Map.of();
        } else {
            authProviders = Map.copyOf(authProviders);
        }

        // 新規構築の場合、デフォルトでfalseにする
        twoFactorAuthEnabled = false;

        return new User(
                notification,
                orderNo,
                email,
                passwordHash,
                twoFactorAuthEnabled,
                authProviders,
                profileImageUrl,
                username);
    }

    /**
     * 再構築用のファクトリーメソッド
     *
     * @param id                   識別子
     * @param orderNo              並び順
     * @param email                メールアドレス
     * @param passwordHash         パスワードハッシュ
     * @param twoFactorAuthEnabled 二段階認証設定
     * @param authProviders        外部認証連携情報
     * @param profileImageUrl      プロフィール画像URL
     * @param username             ユーザー名
     * @param createdAt            作成日時
     * @param updatedAt            更新日時
     * @return Userエンティティ
     */
    public static User reconstruct(UUID id,
            int orderNo,
            Email email,
            String passwordHash,
            boolean twoFactorAuthEnabled,
            Map<String, AuthProvider> authProviders,
            String profileImageUrl,
            String username,
            LocalDateTime createdAt,
            LocalDateTime updatedAt) {

        if (authProviders == null || authProviders.isEmpty()) {
            authProviders = Map.of();
        } else {
            authProviders = Map.copyOf(authProviders);
        }

        return new User(
                id,
                orderNo,
                email,
                passwordHash,
                twoFactorAuthEnabled,
                authProviders,
                profileImageUrl,
                username,
                createdAt,
                updatedAt);
    }

    /**
     * 新規構築時のバリデーション
     */
    private static void validate(Notification notification,
            Email email,
            String passwordHash,
            Map<String, AuthProvider> providers) {

        // メールアドレス未設定かつ外部認証連携情報がなしの場合はログイン手段がないためNG
        if (email == null && providers.isEmpty()) {
            throw new DomainException("ユーザー情報の作成に失敗しました。");
        }
    }

    /**
     * 登録されたドメインイベントを取得する
     */
    public List<DomainEvent> getDomainEvents() {
        return Collections.unmodifiableList(domainEvents);
    }

    /**
     * ドメインイベントをクリアする
     */
    public void clearDomainEvents() {
        domainEvents.clear();
    }

    /**
     * 外部認証プロバイダーを追加する
     *
     * @param notification   通知オブジェクト
     * @param providerName   プロバイダー名
     * @param providerUserId プロバイダー側ユーザーID
     * @return 変更後のUserエンティティ
     */
    public User addAuthProvider(Notification notification,
            String providerName,
            String providerUserId) {

        String key = providerName.toLowerCase();

        // すでに登録済みなら自分自身を返す
        if (this.authProviders.containsKey(key)) {
            return this;
        }

        Map<String, AuthProvider> updated = new HashMap<>(this.authProviders);
        updated.put(key, AuthProvider.create(notification, providerName, providerUserId));

        return new User(
                this.id,
                this.orderNo,
                this.email,
                this.passwordHash,
                this.twoFactorAuthEnabled,
                Map.copyOf(updated), // ← immutable化して渡す
                this.profileImage,
                this.username,
                this.createdAt,
                LocalDateTime.now());
    }

    /**
     * メールアドレスを後から設定する
     *
     * @param notification 通知オブジェクト
     * @param email        メールアドレス
     * @return 変更後のUserエンティティ
     */
    public User setEmail(Notification notification, Email email) {

        // 既にメールアドレスがある場合は設定不可
        if (this.email != null) {
            notification.addError("email", "メールアドレスが既に設定されているため設定できません。");
        }

        if (notification.hasErrors()) {
            throw new DomainException(notification.getErrors());
        }

        return new User(
                this.id,
                this.orderNo,
                email,
                this.passwordHash,
                this.twoFactorAuthEnabled,
                this.authProviders,
                this.profileImage,
                this.username,
                this.createdAt,
                LocalDateTime.now());
    }

    /**
     * パスワードを変更する
     *
     * @param notification    通知オブジェクト
     * @param newPasswordHash 新しいパスワードハッシュ
     * @return 変更後のUserエンティティ
     */
    public User changePassword(Notification notification, String newPasswordHash) {

        // 同じパスワードの場合はNG
        if (newPasswordHash == this.passwordHash) {
            notification.addError("password", "現在のパスワードと同じパスワードは設定できません。");
        }

        if (notification.hasErrors()) {
            throw new DomainException(notification.getErrors());
        }

        return new User(
                this.id,
                this.orderNo,
                this.email,
                newPasswordHash,
                this.twoFactorAuthEnabled,
                this.authProviders,
                this.profileImage,
                this.username,
                this.createdAt,
                LocalDateTime.now());
    }

    /**
     * パスワードをリセットする
     *
     * @param newPasswordHash 新しいパスワードハッシュ
     * @return 変更後のUserエンティティ
     */
    public User resetPassword(String newPasswordHash) {

        return new User(
                this.id,
                this.orderNo,
                this.email,
                newPasswordHash,
                this.twoFactorAuthEnabled,
                this.authProviders,
                this.profileImage,
                this.username,
                this.createdAt,
                LocalDateTime.now());
    }

    /**
     * 二段階認証設定を変更する
     *
     * @param notification         通知オブジェクト
     * @param twoFactorAuthEnabled 二段階認証設定
     * @return 変更後のUserエンティティ
     */
    public User changeTwoFactorAuthEnabled(Notification notification, boolean twoFactorAuthEnabled) {

        // メールアドレスとパスワードが未設定の場合はNG
        if (twoFactorAuthEnabled && (this.email == null || this.passwordHash == null)) {
            notification.addError("twoFactorAuthEnabled", "メールアドレスとパスワードが未設定の場合は二段階認証を有効にできません。");
        }

        if (notification.hasErrors()) {
            throw new DomainException(notification.getErrors());
        }

        return new User(
                this.id,
                this.orderNo,
                this.email,
                this.passwordHash,
                twoFactorAuthEnabled,
                this.authProviders,
                this.profileImage,
                this.username,
                this.createdAt,
                LocalDateTime.now());
    }

    /**
     * 外部認証連携を解除する
     *
     * @param notification 通知オブジェクト
     * @param providerName 削除するプロバイダ名
     * @return 変更後のUserエンティティ
     */
    public User removeAuthProvider(Notification notification, String providerName) {

        String key = providerName.toLowerCase();

        // 対象の外部認証連携情報がない場合NG
        if (!this.authProviders.containsKey(key)) {
            notification.addError("authProviders", "連携の解除に失敗しました。");
            // メールアドレスとパスワードのいずれかが未設定 かつ 外部認証連携が1つしかない場合NG
        } else if ((this.email == null || this.passwordHash == null) && this.authProviders.size() == 1) {
            notification.addError("authProviders", "メールアドレスとパスワードが設定済みでないと、連携を解除できません。");
        }

        if (notification.hasErrors()) {
            throw new DomainException(notification.getErrors());
        }

        Map<String, AuthProvider> updated = new HashMap<>(this.authProviders);
        updated.remove(key);

        return new User(
                this.id,
                this.orderNo,
                this.email,
                this.passwordHash,
                this.twoFactorAuthEnabled,
                Map.copyOf(updated),
                this.profileImage,
                this.username,
                this.createdAt,
                LocalDateTime.now());
    }

    /**
     * プロフィール画像を変更する
     *
     * @param newProfileImage 新しいプロフィール画像
     * @return 変更後のUserエンティティ
     */
    public User changeProfileImage(String newProfileImage) {

        return new User(
                this.id,
                this.orderNo,
                this.email,
                this.passwordHash,
                this.twoFactorAuthEnabled,
                this.authProviders,
                newProfileImage,
                this.username,
                this.createdAt,
                LocalDateTime.now());
    }

    /**
     * ユーザー名を変更する
     *
     * @param notification 通知オブジェクト
     * @param newUsername  新しいユーザー名
     * @return 変更後のUserエンティティ
     */
    public User changeUsername(Notification notification, String newUsername) {

        String trimmed = newUsername == null ? "" : newUsername.strip();

        if (trimmed.isEmpty()) {
            notification.addError("username", "ユーザー名は必ず指定してください。");
        } else if (trimmed.length() > 50) {
            notification.addError("username", "ユーザー名は50文字以内で入力してください。");
        }

        if (notification.hasErrors()) {
            throw new DomainException(notification.getErrors());
        }

        // 変更が無い場合はそのまま返す
        if (trimmed.equals(this.username)) {
            return this;
        }

        return new User(
                this.id,
                this.orderNo,
                this.email,
                this.passwordHash,
                this.twoFactorAuthEnabled,
                this.authProviders,
                this.profileImage,
                trimmed,
                this.createdAt,
                LocalDateTime.now());
    }

    /**
     * ユーザーを削除する
     */
    public void delete() {

        // 削除イベントを発行
        UserDeletedEvent event = new UserDeletedEvent(this.id, this.email.getValue(), this.username);
        this.domainEvents.add(event);
    }
}
