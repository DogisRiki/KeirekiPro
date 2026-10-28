package com.example.keirekipro.domain.model.user;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

import com.example.keirekipro.domain.event.user.UserDeletedEvent;
import com.example.keirekipro.domain.event.user.UserRegisteredEvent;
import com.example.keirekipro.domain.shared.Entity;
import com.example.keirekipro.domain.shared.event.DomainEvent;
import com.example.keirekipro.domain.shared.exception.DomainException;
import com.example.keirekipro.shared.ErrorCollector;

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
     * ロール一覧
     */
    private final Set<RoleName> roles;

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
     * メールアドレスの確認を済ませた日時(nullなら確認前)
     */
    private final LocalDateTime emailVerifiedAt;

    /**
     * 確認を済ませるまでアカウントに付けない、設定待ちのメールアドレス
     */
    private final Email pendingEmail;

    /**
     * ドメインイベント蓄積用
     */
    private final List<DomainEvent> domainEvents = new ArrayList<>();

    /**
     * 新規登録か否かを判定するフラグ
     */
    private final boolean isNew;

    /**
     * 新規構築用のコンストラクタ
     */
    private User(UUID id,
            Email email,
            String passwordHash,
            boolean twoFactorAuthEnabled,
            Map<String, AuthProvider> authProviders,
            Set<RoleName> roles,
            String profileImage,
            String username,
            LocalDateTime emailVerifiedAt) {

        super(id);

        this.email = email;
        this.passwordHash = passwordHash;
        this.twoFactorAuthEnabled = twoFactorAuthEnabled;
        this.authProviders = authProviders;
        // 新規作成時はデフォルトでUSERロールを付与
        this.roles = (roles == null || roles.isEmpty())
                ? EnumSet.of(RoleName.defaultRole())
                : EnumSet.copyOf(roles);
        this.profileImage = profileImage;
        this.username = username;
        this.createdAt = LocalDateTime.now();
        this.updatedAt = LocalDateTime.now();
        this.emailVerifiedAt = emailVerifiedAt;
        this.pendingEmail = null;
        this.isNew = true;
    }

    /**
     * 再構築用のコンストラクタ
     */
    private User(UUID id,
            Email email,
            String passwordHash,
            boolean twoFactorAuthEnabled,
            Map<String, AuthProvider> authProviders,
            Set<RoleName> roles,
            String profileImage,
            String username,
            LocalDateTime createdAt,
            LocalDateTime updatedAt,
            LocalDateTime emailVerifiedAt,
            Email pendingEmail) {
        super(id);

        this.email = email;
        this.passwordHash = passwordHash;
        this.twoFactorAuthEnabled = twoFactorAuthEnabled;
        this.authProviders = authProviders;
        this.roles = (roles == null || roles.isEmpty())
                ? EnumSet.noneOf(RoleName.class)
                : EnumSet.copyOf(roles);
        this.profileImage = profileImage;
        this.username = username;
        this.createdAt = createdAt;
        this.updatedAt = updatedAt;
        this.emailVerifiedAt = emailVerifiedAt;
        this.pendingEmail = pendingEmail;
        this.isNew = false;
    }

    /**
     * 新規構築用のファクトリーメソッド
     *
     * @param errorCollector エラー収集オブジェクト
     * @param email メールアドレス
     * @param passwordHash パスワードハッシュ
     * @param authProviders 外部認証連携情報
     * @param profileImageUrl プロフィール画像
     * @param username ユーザー名
     * @return Userエンティティ
     */
    public static User create(ErrorCollector errorCollector,
            Email email,
            String passwordHash,
            Map<String, AuthProvider> authProviders,
            String profileImageUrl,
            String username) {

        if (authProviders == null || authProviders.isEmpty()) {
            authProviders = Map.of();
        } else {
            authProviders = Map.copyOf(authProviders);
        }

        // 新規構築の場合、デフォルトでfalseにする
        boolean twoFactorAuthEnabled = false;

        Set<RoleName> resolvedRoles = EnumSet.of(RoleName.defaultRole()); // デフォルトロール(USER)を明示的に渡す

        // バリデーション実行
        validate(errorCollector, email, passwordHash, authProviders);

        // 二段階認証が有効な場合、メールアドレスとパスワードが未設定の場合はNG
        if (twoFactorAuthEnabled && (email == null || passwordHash == null)) {
            errorCollector.addError("twoFactorAuthEnabled", "メールアドレスとパスワードが未設定の場合は二段階認証を有効にできません。");
        }

        // 管理者の場合は二段階認証が必須
        validateAdminTwoFactorAuthRequired(errorCollector, resolvedRoles, twoFactorAuthEnabled);

        throwIfInvalid(errorCollector);

        return new User(
                UUID.randomUUID(),
                email,
                passwordHash,
                twoFactorAuthEnabled,
                authProviders,
                resolvedRoles,
                profileImageUrl,
                username,
                null);
    }

    /**
     * 確認を済ませたメールアドレスで新規構築するファクトリーメソッド
     *
     * @param errorCollector エラー収集オブジェクト
     * @param id 識別子
     * @param email 確認を済ませたメールアドレス
     * @param passwordHash パスワードハッシュ
     * @param authProviders 外部認証連携情報
     * @param profileImageUrl プロフィール画像
     * @param username ユーザー名
     * @param verifiedAt メールアドレスの確認を済ませた日時
     * @return Userエンティティ
     */
    public static User createWithVerifiedEmail(ErrorCollector errorCollector,
            UUID id,
            Email email,
            String passwordHash,
            Map<String, AuthProvider> authProviders,
            String profileImageUrl,
            String username,
            LocalDateTime verifiedAt) {

        if (authProviders == null || authProviders.isEmpty()) {
            authProviders = Map.of();
        } else {
            authProviders = Map.copyOf(authProviders);
        }

        validate(errorCollector, email, passwordHash, authProviders);

        throwIfInvalid(errorCollector);

        return new User(
                id,
                email,
                passwordHash,
                false,
                authProviders,
                EnumSet.of(RoleName.defaultRole()),
                profileImageUrl,
                username,
                verifiedAt);
    }

    /**
     * 再構築用のファクトリーメソッド
     *
     * @param id 識別子
     * @param email メールアドレス
     * @param passwordHash パスワードハッシュ
     * @param twoFactorAuthEnabled 二段階認証設定
     * @param authProviders 外部認証連携情報
     * @param roles ロール一覧
     * @param profileImageUrl プロフィール画像URL
     * @param username ユーザー名
     * @param createdAt 作成日時
     * @param updatedAt 更新日時
     * @param emailVerifiedAt メールアドレスの確認を済ませた日時(nullなら確認前)
     * @param pendingEmail 設定待ちのメールアドレス
     * @return Userエンティティ
     */
    public static User reconstruct(UUID id,
            Email email,
            String passwordHash,
            boolean twoFactorAuthEnabled,
            Map<String, AuthProvider> authProviders,
            Set<RoleName> roles,
            String profileImageUrl,
            String username,
            LocalDateTime createdAt,
            LocalDateTime updatedAt,
            LocalDateTime emailVerifiedAt,
            Email pendingEmail) {

        if (authProviders == null || authProviders.isEmpty()) {
            authProviders = Map.of();
        } else {
            authProviders = Map.copyOf(authProviders);
        }

        Set<RoleName> resolvedRoles = (roles == null || roles.isEmpty())
                ? EnumSet.noneOf(RoleName.class)
                : EnumSet.copyOf(roles);

        // 二段階認証が有効な場合、メールアドレスとパスワードが未設定の場合はNG
        if (twoFactorAuthEnabled && (email == null || passwordHash == null)) {
            throw new DomainException("メールアドレスとパスワードが未設定の場合は二段階認証を有効にできません。");
        }

        // 管理者の場合は二段階認証が必須
        if (resolvedRoles.contains(RoleName.ADMIN) && !twoFactorAuthEnabled) {
            throw new DomainException("管理者の場合は二段階認証が必須です。");
        }

        return new User(
                id,
                email,
                passwordHash,
                twoFactorAuthEnabled,
                authProviders,
                resolvedRoles,
                profileImageUrl,
                username,
                createdAt,
                updatedAt,
                emailVerifiedAt,
                pendingEmail);
    }

    /**
     * 新規構築時のバリデーション
     */
    private static void validate(ErrorCollector errorCollector,
            Email email,
            String passwordHash,
            Map<String, AuthProvider> providers) {

        // メールアドレス未設定かつ外部認証連携情報がなしの場合はログイン手段がないためNG
        if (email == null && providers.isEmpty()) {
            errorCollector.addError("user", "ユーザー情報の作成に失敗しました。");
        }
    }

    /**
     * 管理者の場合は二段階認証が必須
     */
    private static void validateAdminTwoFactorAuthRequired(ErrorCollector errorCollector,
            Set<RoleName> roles,
            boolean twoFactorAuthEnabled) {

        if (roles != null && roles.contains(RoleName.ADMIN) && !twoFactorAuthEnabled) {
            errorCollector.addError("twoFactorAuthEnabled", "管理者の場合は二段階認証が必須です。");
        }
    }

    /**
     * errorCollectorにエラーがあればDomainExceptionをスローする
     *
     * @param errorCollector エラー収集オブジェクト
     */
    private static void throwIfInvalid(ErrorCollector errorCollector) {
        if (errorCollector != null && errorCollector.hasErrors()) {
            throw new DomainException(errorCollector.getErrors());
        }
    }

    /**
     * ロール一覧を取得する
     *
     * @return ロール一覧
     */
    public Set<RoleName> getRoles() {
        return Collections.unmodifiableSet(roles);
    }

    /**
     * ロール名の一覧を取得する
     *
     * @return ロール名のSet
     */
    public Set<String> getRoleNames() {
        return roles.stream()
                .map(Enum::name)
                .collect(Collectors.toUnmodifiableSet());
    }

    /**
     * 指定したロールを持っているかを判定する
     *
     * @param role ロール
     * @return 指定したロールを持つ場合true
     */
    public boolean hasRole(RoleName role) {
        return roles.contains(role);
    }

    /**
     * 管理者権限を持っているかを判定する
     *
     * @return 管理者ロールを持つ場合true
     */
    public boolean isAdmin() {
        return roles.contains(RoleName.ADMIN);
    }

    /**
     * ロールを追加する
     *
     * @param errorCollector エラー収集オブジェクト
     * @param role 追加するロール
     * @return 変更後のUserエンティティ
     */
    public User addRole(ErrorCollector errorCollector, RoleName role) {

        if (role == null) {
            errorCollector.addError("roles", "追加するロールが指定されていません。");
        } else if (this.roles.contains(role)) {
            // 既に持っている場合はそのまま返す
            return this;
        }

        // 管理者ロール付与時は二段階認証が必須
        if (role == RoleName.ADMIN && !this.twoFactorAuthEnabled) {
            errorCollector.addError("roles", "管理者ロールを付与するには二段階認証が必須です。");
        }

        // 二段階認証が有効な場合、メールアドレスとパスワードが未設定の場合はNG
        if (this.twoFactorAuthEnabled && (this.email == null || this.passwordHash == null)) {
            errorCollector.addError("twoFactorAuthEnabled", "メールアドレスとパスワードが未設定の場合は二段階認証を有効にできません。");
        }

        if (errorCollector.hasErrors()) {
            throw new DomainException(errorCollector.getErrors());
        }

        EnumSet<RoleName> updatedRoles = toMutableRoleSet(this.roles);
        updatedRoles.add(role);

        return new User(
                this.id,
                this.email,
                this.passwordHash,
                this.twoFactorAuthEnabled,
                this.authProviders,
                EnumSet.copyOf(updatedRoles),
                this.profileImage,
                this.username,
                this.createdAt,
                LocalDateTime.now(),
                this.emailVerifiedAt,
                this.pendingEmail);
    }

    /**
     * ロールを削除する
     *
     * @param errorCollector エラー収集オブジェクト
     * @param role 削除するロール
     * @return 変更後のUserエンティティ
     */
    public User removeRole(ErrorCollector errorCollector, RoleName role) {

        if (role == null) {
            errorCollector.addError("roles", "削除するロールが指定されていません。");
        } else if (!this.roles.contains(role)) {
            errorCollector.addError("roles", "指定されたロールが付与されていないため削除できません。");
        }

        if (errorCollector.hasErrors()) {
            throw new DomainException(errorCollector.getErrors());
        }

        EnumSet<RoleName> updatedRoles = toMutableRoleSet(this.roles);
        updatedRoles.remove(role);

        // ロールが空になる場合はデフォルトロールを付与する
        if (updatedRoles.isEmpty()) {
            updatedRoles.add(RoleName.defaultRole());
        }

        return new User(
                this.id,
                this.email,
                this.passwordHash,
                this.twoFactorAuthEnabled,
                this.authProviders,
                EnumSet.copyOf(updatedRoles),
                this.profileImage,
                this.username,
                this.createdAt,
                LocalDateTime.now(),
                this.emailVerifiedAt,
                this.pendingEmail);
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
     * @param errorCollector エラー収集オブジェクト
     * @param providerName プロバイダー名
     * @param providerUserId プロバイダー側ユーザーID
     * @return 変更後のUserエンティティ
     */
    public User addAuthProvider(ErrorCollector errorCollector,
            String providerName,
            String providerUserId) {

        String key = providerName.toLowerCase();

        // すでに登録済みなら自分自身を返す
        if (this.authProviders.containsKey(key)) {
            return this;
        }

        Map<String, AuthProvider> updated = new HashMap<>(this.authProviders);
        updated.put(key, AuthProvider.create(errorCollector, providerName, providerUserId));

        return new User(
                this.id,
                this.email,
                this.passwordHash,
                this.twoFactorAuthEnabled,
                Map.copyOf(updated),
                this.roles,
                this.profileImage,
                this.username,
                this.createdAt,
                LocalDateTime.now(),
                this.emailVerifiedAt,
                this.pendingEmail);
    }

    /**
     * メールアドレスの確認を済ませているかを判定する
     *
     * @return メールアドレスがあり、確認を済ませていればtrue
     */
    public boolean isEmailVerified() {
        return this.email != null && this.emailVerifiedAt != null;
    }

    /**
     * 今のメールアドレスを確認済みにする
     *
     * @param now 確認を済ませた日時
     * @return 変更後のUserエンティティ
     */
    public User verifyEmail(LocalDateTime now) {

        if (this.email == null) {
            throw new DomainException("メールアドレスが設定されていないため確認できません。");
        }

        // すでに確認済みなら日時を変えない
        if (this.emailVerifiedAt != null) {
            return this;
        }

        return new User(
                this.id,
                this.email,
                this.passwordHash,
                this.twoFactorAuthEnabled,
                this.authProviders,
                this.roles,
                this.profileImage,
                this.username,
                this.createdAt,
                LocalDateTime.now(),
                now,
                this.pendingEmail);
    }

    /**
     * 設定待ちのメールアドレスを設定する(既にあれば置き換える)
     *
     * @param errorCollector エラー収集オブジェクト
     * @param email 設定待ちにするメールアドレス
     * @return 変更後のUserエンティティ
     */
    public User setPendingEmail(ErrorCollector errorCollector, Email email) {

        // 既にメールアドレスがある場合は設定不可
        if (this.email != null) {
            errorCollector.addError("email", "メールアドレスが既に設定されているため設定できません。");
        }

        if (errorCollector.hasErrors()) {
            throw new DomainException(errorCollector.getErrors());
        }

        return new User(
                this.id,
                this.email,
                this.passwordHash,
                this.twoFactorAuthEnabled,
                this.authProviders,
                this.roles,
                this.profileImage,
                this.username,
                this.createdAt,
                LocalDateTime.now(),
                this.emailVerifiedAt,
                email);
    }

    /**
     * 設定待ちのメールアドレスを、確認済みのメールアドレスにする
     *
     * @param now 確認を済ませた日時
     * @return 変更後のUserエンティティ
     */
    public User promotePendingEmail(LocalDateTime now) {

        if (this.email != null || this.pendingEmail == null) {
            throw new DomainException("設定待ちのメールアドレスが無いため確認できません。");
        }

        return new User(
                this.id,
                this.pendingEmail,
                this.passwordHash,
                this.twoFactorAuthEnabled,
                this.authProviders,
                this.roles,
                this.profileImage,
                this.username,
                this.createdAt,
                LocalDateTime.now(),
                now,
                null);
    }

    /**
     * パスワードを変更する
     *
     * @param errorCollector エラー収集オブジェクト
     * @param newPasswordHash 新しいパスワードハッシュ
     * @return 変更後のUserエンティティ
     */
    public User changePassword(ErrorCollector errorCollector, String newPasswordHash) {

        // 同じパスワードの場合はNG
        if (java.util.Objects.equals(newPasswordHash, this.passwordHash)) {
            errorCollector.addError("password", "現在のパスワードと同じパスワードは設定できません。");
        }

        if (errorCollector.hasErrors()) {
            throw new DomainException(errorCollector.getErrors());
        }

        return new User(
                this.id,
                this.email,
                newPasswordHash,
                this.twoFactorAuthEnabled,
                this.authProviders,
                this.roles,
                this.profileImage,
                this.username,
                this.createdAt,
                LocalDateTime.now(),
                this.emailVerifiedAt,
                this.pendingEmail);
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
                this.email,
                newPasswordHash,
                this.twoFactorAuthEnabled,
                this.authProviders,
                this.roles,
                this.profileImage,
                this.username,
                this.createdAt,
                LocalDateTime.now(),
                this.emailVerifiedAt,
                this.pendingEmail);
    }

    /**
     * 二段階認証設定を変更する
     *
     * @param errorCollector エラー収集オブジェクト
     * @param twoFactorAuthEnabled 二段階認証設定
     * @return 変更後のUserエンティティ
     */
    public User changeTwoFactorAuthEnabled(ErrorCollector errorCollector, boolean twoFactorAuthEnabled) {

        // 管理者の場合は無効化不可
        if (this.isAdmin() && !twoFactorAuthEnabled) {
            errorCollector.addError("twoFactorAuthEnabled", "管理者の場合は二段階認証を無効にできません。");
        }

        // 確認済みのメールアドレスとパスワードが未設定の場合はNG(確認前と設定待ちのメールアドレスは無いものとして扱う)
        if (twoFactorAuthEnabled && (!this.isEmailVerified() || this.passwordHash == null)) {
            errorCollector.addError("twoFactorAuthEnabled", "メールアドレスとパスワードが未設定の場合は二段階認証を有効にできません。");
        }

        if (errorCollector.hasErrors()) {
            throw new DomainException(errorCollector.getErrors());
        }

        return new User(
                this.id,
                this.email,
                this.passwordHash,
                twoFactorAuthEnabled,
                this.authProviders,
                this.roles,
                this.profileImage,
                this.username,
                this.createdAt,
                LocalDateTime.now(),
                this.emailVerifiedAt,
                this.pendingEmail);
    }

    /**
     * 外部認証連携を解除する
     *
     * @param errorCollector エラー収集オブジェクト
     * @param providerName 削除するプロバイダ名
     * @return 変更後のUserエンティティ
     */
    public User removeAuthProvider(ErrorCollector errorCollector, String providerName) {

        String key = providerName.toLowerCase();

        // 対象の外部認証連携情報がない場合NG
        if (!this.authProviders.containsKey(key)) {
            errorCollector.addError("authProviders", "連携の解除に失敗しました。");
            // 確認済みのメールアドレスとパスワードのいずれかが未設定 かつ 外部認証連携が1つしかない場合NG
            // (確認前と設定待ちのメールアドレスは無いものとして扱う)
        } else if ((!this.isEmailVerified() || this.passwordHash == null) && this.authProviders.size() == 1) {
            errorCollector.addError("authProviders", "メールアドレスとパスワードが設定済みでないと、連携を解除できません。");
        }

        if (errorCollector.hasErrors()) {
            throw new DomainException(errorCollector.getErrors());
        }

        Map<String, AuthProvider> updated = new HashMap<>(this.authProviders);
        updated.remove(key);

        return new User(
                this.id,
                this.email,
                this.passwordHash,
                this.twoFactorAuthEnabled,
                Map.copyOf(updated),
                this.roles,
                this.profileImage,
                this.username,
                this.createdAt,
                LocalDateTime.now(),
                this.emailVerifiedAt,
                this.pendingEmail);
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
                this.email,
                this.passwordHash,
                this.twoFactorAuthEnabled,
                this.authProviders,
                this.roles,
                newProfileImage,
                this.username,
                this.createdAt,
                LocalDateTime.now(),
                this.emailVerifiedAt,
                this.pendingEmail);
    }

    /**
     * ユーザー名を変更する
     *
     * @param errorCollector エラー収集オブジェクト
     * @param newUsername 新しいユーザー名
     * @return 変更後のUserエンティティ
     */
    public User changeUsername(ErrorCollector errorCollector, String newUsername) {

        String trimmed = newUsername == null ? "" : newUsername.strip();

        if (trimmed.isEmpty()) {
            errorCollector.addError("username", "ユーザー名は必ず指定してください。");
        } else if (trimmed.length() > 50) {
            errorCollector.addError("username", "ユーザー名は50文字以内で入力してください。");
        }

        if (errorCollector.hasErrors()) {
            throw new DomainException(errorCollector.getErrors());
        }

        // 変更が無い場合はそのまま返す
        if (trimmed.equals(this.username)) {
            return this;
        }

        return new User(
                this.id,
                this.email,
                this.passwordHash,
                this.twoFactorAuthEnabled,
                this.authProviders,
                this.roles,
                this.profileImage,
                trimmed,
                this.createdAt,
                LocalDateTime.now(),
                this.emailVerifiedAt,
                this.pendingEmail);
    }

    /**
     * ユーザーを新規登録する
     */
    public void register() {

        // 新規登録時しか呼び出せないようにする
        if (!isNew) {
            throw new IllegalStateException("このユーザーは新規作成ではありません。");
        }

        // 新規登録イベントを発行
        UserRegisteredEvent event = new UserRegisteredEvent(id, this.email.getValue(), username);
        this.domainEvents.add(event);
    }

    /**
     * ユーザーを削除する
     */
    public void delete() {

        // 確認前と設定待ちのメールアドレスには退会のお知らせを送らないため、イベントを発行しない
        if (!this.isEmailVerified()) {
            return;
        }

        // 削除イベントを発行
        UserDeletedEvent event = new UserDeletedEvent(this.id, this.email.getValue(), this.username);
        this.domainEvents.add(event);
    }

    /**
     * ロールの可変EnumSetを作成する
     *
     * @param roles ロール一覧
     * @return 可変のEnumSet
     */
    private static EnumSet<RoleName> toMutableRoleSet(Set<RoleName> roles) {

        EnumSet<RoleName> set = EnumSet.noneOf(RoleName.class);

        if (roles != null) {
            set.addAll(roles);
        }

        return set;
    }
}
