package com.example.keirekipro.unit.domain.model.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import com.example.keirekipro.domain.event.user.UserDeletedEvent;
import com.example.keirekipro.domain.event.user.UserRegisteredEvent;
import com.example.keirekipro.domain.model.user.AuthProvider;
import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.RoleName;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.shared.exception.DomainException;
import com.example.keirekipro.shared.ErrorCollector;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class UserTest {

    @Mock
    private ErrorCollector errorCollector;

    private static final UUID ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final String EMAIL = "test@keirekipro.click";
    private static final String PASSWORD_HASH = "passwordHash";
    private static final String USERNAME = "test-user";
    private static final Map<String, AuthProvider> AUTH_PROVIDERS = Map.of("google",
            AuthProvider.create(new ErrorCollector(), "google", "googleId"));
    private static final String PROFILE_IMAGE = "profile/test-user.jpg";
    private static final LocalDateTime CREATED_AT = LocalDateTime.of(2023, 1, 1, 0, 0);
    private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2023, 1, 2, 0, 0);
    private static final LocalDateTime EMAIL_VERIFIED_AT = LocalDateTime.of(2023, 1, 1, 12, 0);
    private static final LocalDateTime NOW = LocalDateTime.of(2024, 6, 1, 9, 0);

    @Test
    @DisplayName("メールアドレス+パスワードで新規構築用コンストラクタでインスタンス化する")
    void test1() {
        ErrorCollector errorCollector = new ErrorCollector();
        Email email = Email.create(new ErrorCollector(), EMAIL);

        User user = User.create(
                errorCollector,
                email,
                PASSWORD_HASH,
                Collections.emptyMap(),
                null,
                USERNAME);

        // ユーザーが正しく生成されたことを検証
        assertThat(user).isNotNull();

        // errorCollector内にエラーが登録されていないことを検証
        assertThat(errorCollector.hasErrors()).isFalse();

        // 各フィールドが期待した値になっていることを検証
        assertThat(user.getId()).isNotNull();
        assertThat(user.getEmail()).isEqualTo(email);
        assertThat(user.getPasswordHash()).isEqualTo(PASSWORD_HASH);
        assertThat(user.isTwoFactorAuthEnabled()).isFalse(); // 新規作成時は常にfalse
        assertThat(user.getAuthProviders()).isEmpty();
        assertThat(user.getProfileImage()).isNull();
        assertThat(user.getUsername()).isEqualTo(USERNAME);
        assertThat(user.getCreatedAt()).isNotNull();
        assertThat(user.getUpdatedAt()).isNotNull();
        assertThat(user.isNew()).isTrue();

        // ロールがデフォルト(USER)で付与されていることを検証
        assertThat(user.getRoles()).containsExactly(RoleName.USER);
        assertThat(user.isAdmin()).isFalse();
        assertThat(user.hasRole(RoleName.USER)).isTrue();
    }

    @Test
    @DisplayName("外部認証連携で新規構築用コンストラクタでインスタンス化する")
    void test2() {
        ErrorCollector errorCollector = new ErrorCollector();
        Email email = Email.create(new ErrorCollector(), EMAIL);

        User user = User.create(
                errorCollector,
                email,
                null,
                AUTH_PROVIDERS,
                null,
                USERNAME);

        // ユーザーが正しく生成されたことを検証
        assertThat(user).isNotNull();

        // errorCollector内にエラーが登録されていないことを検証
        assertThat(errorCollector.hasErrors()).isFalse();

        // 各フィールドが期待した値になっていることを検証
        assertThat(user.getId()).isNotNull();
        assertThat(user.getEmail()).isEqualTo(email);
        assertThat(user.getPasswordHash()).isNull();
        assertThat(user.isTwoFactorAuthEnabled()).isFalse();
        assertThat(user.getAuthProviders()).isEqualTo(AUTH_PROVIDERS);
        assertThat(user.getProfileImage()).isNull();
        assertThat(user.getUsername()).isEqualTo(USERNAME);
        assertThat(user.getCreatedAt()).isNotNull();
        assertThat(user.getUpdatedAt()).isNotNull();
        assertThat(user.isNew()).isTrue();

        // ロールがデフォルト(USER)で付与されていることを検証
        assertThat(user.getRoles()).containsExactly(RoleName.USER);
        assertThat(user.isAdmin()).isFalse();
    }

    @Test
    @DisplayName("外部認証連携かつメールアドレスなしで新規構築用コンストラクタでインスタンス化する")
    void test3() {
        ErrorCollector errorCollector = new ErrorCollector();
        User user = User.create(
                errorCollector,
                null,
                null,
                AUTH_PROVIDERS,
                null,
                USERNAME);

        // ユーザーが正しく生成されたことを検証
        assertThat(user).isNotNull();

        // errorCollector内にエラーが登録されていないことを検証
        assertThat(errorCollector.hasErrors()).isFalse();

        // 各フィールドが期待した値になっていることを検証
        assertThat(user.getId()).isNotNull();
        assertThat(user.getEmail()).isNull();
        assertThat(user.getPasswordHash()).isNull();
        assertThat(user.isTwoFactorAuthEnabled()).isFalse();
        assertThat(user.getAuthProviders()).isEqualTo(AUTH_PROVIDERS);
        assertThat(user.getProfileImage()).isNull();
        assertThat(user.getUsername()).isEqualTo(USERNAME);
        assertThat(user.getCreatedAt()).isNotNull();
        assertThat(user.getUpdatedAt()).isNotNull();
        assertThat(user.isNew()).isTrue();

        // ロールがデフォルト(USER)で付与されていることを検証
        assertThat(user.getRoles()).containsExactly(RoleName.USER);
        assertThat(user.isAdmin()).isFalse();
    }

    @Test
    @DisplayName("メールアドレスが未設定かつ外部認証連携がなしの状態で、新規構築用コンストラクタでインスタンス化するとDomainExceptionをスローする")
    void test4() {
        ErrorCollector errorCollector = new ErrorCollector();
        assertThatThrownBy(() -> User.create(
                errorCollector,
                null,
                PASSWORD_HASH,
                Collections.emptyMap(),
                null,
                USERNAME)).isInstanceOf(DomainException.class);
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test5() {
        Email email = Email.create(new ErrorCollector(), EMAIL);
        User user = User.reconstruct(
                ID,
                email,
                PASSWORD_HASH,
                true,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        // ユーザーが正しく生成されたことを検証
        assertThat(user).isNotNull();

        // 各フィールドが期待した値になっていることを検証
        assertThat(user.getId()).isEqualTo(ID);
        assertThat(user.getEmail()).isEqualTo(email);
        assertThat(user.getPasswordHash()).isEqualTo(PASSWORD_HASH);
        assertThat(user.isTwoFactorAuthEnabled()).isTrue();
        assertThat(user.getAuthProviders()).isEqualTo(AUTH_PROVIDERS);
        assertThat(user.getProfileImage()).isEqualTo(PROFILE_IMAGE);
        assertThat(user.getUsername()).isEqualTo(USERNAME);
        assertThat(user.getCreatedAt()).isEqualTo(CREATED_AT);
        assertThat(user.getUpdatedAt()).isEqualTo(UPDATED_AT);
        assertThat(user.isNew()).isFalse();

        // ロールが保持されていることを検証
        assertThat(user.getRoles()).containsExactly(RoleName.USER);
        assertThat(user.isAdmin()).isFalse();
    }

    @Test
    @DisplayName("メールアドレスを設定する")
    void test6() {
        User user = User.reconstruct(
                ID,
                null,
                PASSWORD_HASH,
                false,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        User updatedUser = user.setEmail(errorCollector, Email.create(new ErrorCollector(), "new@keirekipro.click"));
        assertThat(updatedUser.getEmail().getValue()).isEqualTo("new@keirekipro.click");
        verify(errorCollector, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("既にメールアドレスが設定されている状態でメールアドレスを設定するとDomainExceptionをスローする")
    void test7() {
        // モックをセットアップ
        when(errorCollector.hasErrors()).thenReturn(true);

        Email email = Email.create(errorCollector, EMAIL);
        User user = User.reconstruct(
                ID,
                email,
                PASSWORD_HASH,
                true,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> {
            User ignored = user.setEmail(errorCollector, Email.create(errorCollector, "other@keirekipro.click"));
            assertThat(ignored).isNotNull();
        }).isInstanceOf(DomainException.class);

        // エラーメッセージが登録される
        verify(errorCollector, times(1)).addError(eq("email"), eq("メールアドレスが既に設定されているため設定できません。"));
    }

    @Test
    @DisplayName("パスワードを変更する")
    void test8() {
        Email email = Email.create(errorCollector, EMAIL);
        User user = User.reconstruct(
                ID,
                email,
                PASSWORD_HASH,
                true,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        User updatedUser = user.changePassword(errorCollector, "updatedHashPassword");
        assertThat(updatedUser.getPasswordHash()).isEqualTo("updatedHashPassword");
        verify(errorCollector, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("現在と同じパスワードに変更するとDomainExceptionをスローする")
    void test9() {
        // モックをセットアップ
        when(errorCollector.hasErrors()).thenReturn(true);

        Email email = Email.create(errorCollector, EMAIL);
        User user = User.reconstruct(
                ID,
                email,
                PASSWORD_HASH,
                true,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> {
            User ignored = user.changePassword(errorCollector, PASSWORD_HASH);
            assertThat(ignored).isNotNull();
        }).isInstanceOf(DomainException.class);

        // エラーメッセージが登録される
        verify(errorCollector, times(1)).addError(eq("password"), eq("現在のパスワードと同じパスワードは設定できません。"));
    }

    @Test
    @DisplayName("二段階認証設定を変更する(無効から有効)")
    void test10() {
        Email email = Email.create(errorCollector, EMAIL);
        User user = User.reconstruct(
                ID,
                email,
                PASSWORD_HASH,
                false,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        User updatedUser = user.changeTwoFactorAuthEnabled(errorCollector, true);
        assertThat(updatedUser.isTwoFactorAuthEnabled()).isTrue();
        verify(errorCollector, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("二段階認証設定を変更する(有効から無効)")
    void test11() {
        Email email = Email.create(errorCollector, EMAIL);
        User user = User.reconstruct(
                ID,
                email,
                PASSWORD_HASH,
                true,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        User updatedUser = user.changeTwoFactorAuthEnabled(errorCollector, false);
        assertThat(updatedUser.isTwoFactorAuthEnabled()).isFalse();
        verify(errorCollector, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("メールアドレスまたはパスワードのどちらか片方でも未設定の状態で二段階認証設定を有効にするとDomainExceptionをスローする")
    void test12() {
        // モックをセットアップ
        when(errorCollector.hasErrors()).thenReturn(true);

        // メールアドレスとパスワードが未設定
        User user1 = User.reconstruct(
                ID,
                null,
                null,
                false,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> {
            User ignored = user1.changeTwoFactorAuthEnabled(errorCollector, true);
            assertThat(ignored).isNotNull();
        }).isInstanceOf(DomainException.class);

        // パスワードが未設定
        Email email = Email.create(errorCollector, EMAIL);
        User user2 = User.reconstruct(
                ID,
                email,
                null,
                false,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> {
            User ignored = user2.changeTwoFactorAuthEnabled(errorCollector, true);
            assertThat(ignored).isNotNull();
        }).isInstanceOf(DomainException.class);

        // 合計2回呼ばれる
        verify(errorCollector, times(2)).addError(eq("twoFactorAuthEnabled"),
                eq("メールアドレスとパスワードが未設定の場合は二段階認証を有効にできません。"));
    }

    @Test
    @DisplayName("外部認証連携が1つ+メールアドレスとパスワードが設定済み状態の場合、外部認証連携を解除できる")
    void test13() {
        Email email = Email.create(errorCollector, EMAIL);
        User user = User.reconstruct(
                ID,
                email,
                PASSWORD_HASH,
                false,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        User updatedUser = user.removeAuthProvider(errorCollector, "google");
        assertThat(updatedUser.getAuthProviders()).isEmpty();
        verify(errorCollector, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("外部認証連携が2つの状態の場合、外部認証連携を解除できる")
    void test14() {
        Email email = Email.create(errorCollector, EMAIL);
        Map<String, AuthProvider> providers = new HashMap<>();
        providers.put("google", AuthProvider.create(new ErrorCollector(), "google", "googleId"));
        providers.put("github", AuthProvider.create(new ErrorCollector(), "github", "githubId"));

        User user = User.reconstruct(
                ID,
                email,
                null,
                false,
                providers,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        User updated = user.removeAuthProvider(errorCollector, "google");
        assertThat(updated.getAuthProviders()).hasSize(1);
        assertThat(updated.getAuthProviders()).doesNotContainKey("google");
        assertThat(updated.getAuthProviders()).containsKey("github");
        verify(errorCollector, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("連携済みでない外部認証連携を解除しようとするとDomainExceptionをスローする")
    void test15() {
        // モックをセットアップ
        when(errorCollector.hasErrors()).thenReturn(true);

        Email email = Email.create(errorCollector, EMAIL);
        User user = User.reconstruct(
                ID,
                email,
                PASSWORD_HASH,
                false,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> {
            User ignored = user.removeAuthProvider(errorCollector, "github");
            assertThat(ignored).isNotNull();
        }).isInstanceOf(DomainException.class);

        // エラーメッセージが登録される
        verify(errorCollector, times(1)).addError(eq("authProviders"), eq("連携の解除に失敗しました。"));
    }

    @Test
    @DisplayName("メールアドレスとパスワードが未設定かつ外部認証連携情報が1つしか登録されていない状態で、外部認証連携を解除しようとするとDomainExceptionをスローする")
    void test16() {
        // モックをセットアップ
        when(errorCollector.hasErrors()).thenReturn(true);

        User user = User.reconstruct(
                ID,
                null,
                PASSWORD_HASH,
                false,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> {
            User ignored = user.removeAuthProvider(errorCollector, "google");
            assertThat(ignored).isNotNull();
        }).isInstanceOf(DomainException.class);

        // エラーメッセージが登録される
        verify(errorCollector, times(1)).addError(eq("authProviders"), eq("メールアドレスとパスワードが設定済みでないと、連携を解除できません。"));
    }

    @Test
    @DisplayName("プロフィール画像を変更する")
    void test17() {
        User user = User.reconstruct(
                ID,
                null,
                PASSWORD_HASH,
                false,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        User updatedUser = user.changeProfileImage("profile/new-user.png");
        assertThat(updatedUser.getProfileImage()).isEqualTo("profile/new-user.png");
    }

    @Test
    @DisplayName("ユーザー名を変更する")
    void test18() {
        User user = User.reconstruct(
                ID,
                null,
                PASSWORD_HASH,
                false,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        User updatedUser = user.changeUsername(errorCollector, "new-name");
        assertThat(updatedUser.getUsername()).isEqualTo("new-name");
        verify(errorCollector, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("ユーザー名を空文字に変更するとDomainExceptionをスローする")
    void test19() {
        // モックをセットアップ
        when(errorCollector.hasErrors()).thenReturn(true);

        User user = User.reconstruct(
                ID,
                null,
                PASSWORD_HASH,
                false,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> {
            User ignored = user.changeUsername(errorCollector, " ");
            assertThat(ignored).isNotNull();
        }).isInstanceOf(DomainException.class);

        // エラーメッセージが登録される
        verify(errorCollector, times(1)).addError(eq("username"), eq("ユーザー名は必ず指定してください。"));
    }

    @Test
    @DisplayName("外部認証プロバイダーを追加する(未登録の場合)")
    void test20() {
        User user = User.reconstruct(
                ID,
                null,
                PASSWORD_HASH,
                false,
                new HashMap<>(AUTH_PROVIDERS),
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        User updatedUser = user.addAuthProvider(errorCollector, "github", "githubId");

        assertThat(updatedUser.getAuthProviders()).containsKey("github");
        verify(errorCollector, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("既に登録済みの外部認証プロバイダーを追加しようとしても何もしない")
    void test21() {
        User user = User.reconstruct(
                ID,
                null,
                PASSWORD_HASH,
                false,
                new HashMap<>(AUTH_PROVIDERS),
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        user.addAuthProvider(errorCollector, "google", "otherId");

        // 変更されていないことを検証
        assertThat(user.getAuthProviders()).hasSize(1);
        assertThat(user.getAuthProviders().get("google").getProviderUserId()).isEqualTo("googleId");
        verify(errorCollector, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("パスワードをリセットする")
    void test22() {
        Email email = Email.create(errorCollector, EMAIL);
        User user = User.reconstruct(
                ID,
                email,
                PASSWORD_HASH,
                true,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        User updatedUser = user.resetPassword("newResetPasswordHash");

        assertThat(updatedUser.getPasswordHash()).isEqualTo("newResetPasswordHash");
        assertThat(updatedUser.getId()).isEqualTo(ID);
        assertThat(updatedUser.getEmail()).isEqualTo(email);
        assertThat(updatedUser.getUsername()).isEqualTo(USERNAME);
        assertThat(updatedUser.getAuthProviders()).isEqualTo(AUTH_PROVIDERS);
        verify(errorCollector, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("ユーザー登録でUserRegisteredEventが追加される")
    void test23() {
        Email email = Email.create(errorCollector, EMAIL);
        User user = User.create(
                errorCollector,
                email,
                PASSWORD_HASH,
                Collections.emptyMap(),
                null,
                USERNAME);

        user.register();

        assertThat(user.getDomainEvents()).hasSize(1);
        assertThat(user.getDomainEvents().get(0)).isInstanceOf(UserRegisteredEvent.class);
        UserRegisteredEvent event = (UserRegisteredEvent) user.getDomainEvents().get(0);
        assertThat(event.getUserId()).isEqualTo(user.getId());
        assertThat(event.getEmail()).isEqualTo(email.getValue());
        assertThat(event.getUsername()).isEqualTo(USERNAME);
    }

    @Test
    @DisplayName("再構築時にregister()を呼び出すとIllegalStateExceptionがスローされる")
    void test24() {
        Email email = Email.create(errorCollector, EMAIL);
        User user = User.reconstruct(
                ID,
                email,
                PASSWORD_HASH,
                true,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        // IllegalStateExceptionがスローされる
        assertThatThrownBy(() -> user.register()).isInstanceOf(IllegalStateException.class);
    }

    @Test
    @DisplayName("ユーザー削除でUserDeletedEventが追加される")
    void test25() {
        Email email = Email.create(errorCollector, EMAIL);
        User user = User.reconstruct(
                ID,
                email,
                PASSWORD_HASH,
                false,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        user.delete();

        assertThat(user.getDomainEvents()).hasSize(1);
        assertThat(user.getDomainEvents().get(0)).isInstanceOf(UserDeletedEvent.class);
        UserDeletedEvent event = (UserDeletedEvent) user.getDomainEvents().get(0);
        assertThat(event.getUserId()).isEqualTo(ID);
        assertThat(event.getEmail()).isEqualTo(email.getValue());
        assertThat(event.getUsername()).isEqualTo(USERNAME);
    }

    @Test
    @DisplayName("二段階認証が無効な状態で管理者ロールを付与しようとするとDomainExceptionをスローする")
    void test26() {
        // モックをセットアップ
        when(errorCollector.hasErrors()).thenReturn(true);

        Email email = Email.create(new ErrorCollector(), EMAIL);
        User user = User.reconstruct(
                ID,
                email,
                PASSWORD_HASH,
                false,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> {
            User ignored = user.addRole(errorCollector, RoleName.ADMIN);
            assertThat(ignored).isNotNull();
        }).isInstanceOf(DomainException.class);

        // エラーメッセージが登録される
        verify(errorCollector, times(1)).addError(eq("roles"), eq("管理者ロールを付与するには二段階認証が必須です。"));
    }

    @Test
    @DisplayName("ロールを削除して空になる場合はデフォルトロール(USER)が付与される")
    void test27() {
        Email email = Email.create(new ErrorCollector(), EMAIL);
        User user = User.reconstruct(
                ID,
                email,
                PASSWORD_HASH,
                false,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        User updatedUser = user.removeRole(errorCollector, RoleName.USER);

        assertThat(updatedUser.getRoles()).containsExactly(RoleName.USER);
        verify(errorCollector, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("管理者ロール付与後に二段階認証を無効化しようとするとDomainExceptionをスローする")
    void test28() {
        // モックをセットアップ
        when(errorCollector.hasErrors()).thenReturn(true);

        Email email = Email.create(new ErrorCollector(), EMAIL);
        User user = User.reconstruct(
                ID,
                email,
                PASSWORD_HASH,
                true,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.ADMIN),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null);

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> {
            User ignored = user.changeTwoFactorAuthEnabled(errorCollector, false);
            assertThat(ignored).isNotNull();
        }).isInstanceOf(DomainException.class);

        // エラーメッセージが登録される
        verify(errorCollector, times(1)).addError(eq("twoFactorAuthEnabled"), eq("管理者の場合は二段階認証を無効にできません。"));
    }

    @Test
    @DisplayName("管理者ロールかつ二段階認証が無効の状態で再構築するとDomainExceptionをスローする")
    void test29() {
        Email email = Email.create(new ErrorCollector(), EMAIL);

        assertThatThrownBy(() -> User.reconstruct(
                ID,
                email,
                PASSWORD_HASH,
                false,
                AUTH_PROVIDERS,
                EnumSet.of(RoleName.ADMIN),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                EMAIL_VERIFIED_AT,
                null)).isInstanceOf(DomainException.class)
                .hasMessageContaining("管理者の場合は二段階認証が必須です。");
    }

    @Test
    @DisplayName("isEmailVerified はメールアドレスと確認の日時がどちらもあるときだけ true を返す")
    void test30() {
        Email email = Email.create(new ErrorCollector(), EMAIL);

        assertThat(reconstructUser(email, PASSWORD_HASH, false, AUTH_PROVIDERS, EMAIL_VERIFIED_AT, null)
                .isEmailVerified()).isTrue();
        assertThat(reconstructUser(email, PASSWORD_HASH, false, AUTH_PROVIDERS, null, null)
                .isEmailVerified()).isFalse();
        assertThat(reconstructUser(null, PASSWORD_HASH, false, AUTH_PROVIDERS, EMAIL_VERIFIED_AT, null)
                .isEmailVerified()).isFalse();
    }

    @Test
    @DisplayName("createWithVerifiedEmail は指定した ID と確認済みのメールアドレスで新規のユーザーを作る")
    void test31() {
        Email email = Email.create(new ErrorCollector(), EMAIL);

        User user = User.createWithVerifiedEmail(new ErrorCollector(), ID, email, PASSWORD_HASH, null, null,
                USERNAME, NOW);

        assertThat(user.getId()).isEqualTo(ID);
        assertThat(user.getEmail()).isEqualTo(email);
        assertThat(user.getPasswordHash()).isEqualTo(PASSWORD_HASH);
        assertThat(user.getUsername()).isEqualTo(USERNAME);
        assertThat(user.getEmailVerifiedAt()).isEqualTo(NOW);
        assertThat(user.getPendingEmail()).isNull();
        assertThat(user.isEmailVerified()).isTrue();
        assertThat(user.isTwoFactorAuthEnabled()).isFalse();
        assertThat(user.getRoles()).containsExactly(RoleName.USER);

        // 新規のユーザーなので register() で UserRegisteredEvent を積める
        user.register();
        assertThat(user.getDomainEvents()).hasSize(1);
        assertThat(user.getDomainEvents().get(0)).isInstanceOf(UserRegisteredEvent.class);
    }

    @Test
    @DisplayName("create で作ったユーザーのメールアドレスは確認前になる")
    void test32() {
        User user = User.create(new ErrorCollector(), Email.create(new ErrorCollector(), EMAIL), PASSWORD_HASH,
                null, null, USERNAME);

        assertThat(user.getEmailVerifiedAt()).isNull();
        assertThat(user.getPendingEmail()).isNull();
        assertThat(user.isEmailVerified()).isFalse();
    }

    @Test
    @DisplayName("verifyEmail は emailVerifiedAt が null のときだけ日時を入れる")
    void test33() {
        Email email = Email.create(new ErrorCollector(), EMAIL);

        User unverified = reconstructUser(email, PASSWORD_HASH, false, AUTH_PROVIDERS, null, null);
        User verified = unverified.verifyEmail(NOW);
        assertThat(verified.getEmailVerifiedAt()).isEqualTo(NOW);
        assertThat(verified.getEmail()).isEqualTo(email);
        assertThat(verified.isEmailVerified()).isTrue();

        // すでに確認済みなら日時を変えない
        User alreadyVerified = reconstructUser(email, PASSWORD_HASH, false, AUTH_PROVIDERS, EMAIL_VERIFIED_AT, null);
        assertThat(alreadyVerified.verifyEmail(NOW).getEmailVerifiedAt()).isEqualTo(EMAIL_VERIFIED_AT);
    }

    @Test
    @DisplayName("メールアドレスの無いアカウントで verifyEmail を呼ぶと DomainException をスローする")
    void test34() {
        User user = reconstructUser(null, PASSWORD_HASH, false, AUTH_PROVIDERS, null, null);

        assertThatThrownBy(() -> {
            User ignored = user.verifyEmail(NOW);
            assertThat(ignored).isNotNull();
        }).isInstanceOf(DomainException.class);
    }

    @Test
    @DisplayName("setPendingEmail は email の無いアカウントの pendingEmail を置き換える")
    void test35() {
        Email oldPending = Email.create(new ErrorCollector(), "old@keirekipro.click");
        Email newPending = Email.create(new ErrorCollector(), "new@keirekipro.click");
        User user = reconstructUser(null, PASSWORD_HASH, false, AUTH_PROVIDERS, null, oldPending);

        User updated = user.setPendingEmail(new ErrorCollector(), newPending);

        assertThat(updated.getPendingEmail()).isEqualTo(newPending);
        assertThat(updated.getEmail()).isNull();
        assertThat(updated.getEmailVerifiedAt()).isNull();
        assertThat(updated.isEmailVerified()).isFalse();
    }

    @Test
    @DisplayName("メールアドレスのあるアカウントで setPendingEmail を呼ぶと DomainException をスローする")
    void test36() {
        when(errorCollector.hasErrors()).thenReturn(true);
        Email email = Email.create(new ErrorCollector(), EMAIL);
        User user = reconstructUser(email, PASSWORD_HASH, false, AUTH_PROVIDERS, null, null);

        assertThatThrownBy(() -> {
            User ignored = user.setPendingEmail(errorCollector,
                    Email.create(new ErrorCollector(), "new@keirekipro.click"));
            assertThat(ignored).isNotNull();
        }).isInstanceOf(DomainException.class);

        verify(errorCollector, times(1)).addError(eq("email"), eq("メールアドレスが既に設定されているため設定できません。"));
    }

    @Test
    @DisplayName("promotePendingEmail は pendingEmail を email に移し emailVerifiedAt を入れる")
    void test37() {
        Email pending = Email.create(new ErrorCollector(), "pending@keirekipro.click");
        User user = reconstructUser(null, PASSWORD_HASH, false, AUTH_PROVIDERS, null, pending);

        User promoted = user.promotePendingEmail(NOW);

        assertThat(promoted.getEmail()).isEqualTo(pending);
        assertThat(promoted.getPendingEmail()).isNull();
        assertThat(promoted.getEmailVerifiedAt()).isEqualTo(NOW);
        assertThat(promoted.isEmailVerified()).isTrue();
    }

    @Test
    @DisplayName("設定待ちのメールアドレスが無いか、メールアドレスがあるときに promotePendingEmail を呼ぶと DomainException をスローする")
    void test38() {
        User noPending = reconstructUser(null, PASSWORD_HASH, false, AUTH_PROVIDERS, null, null);
        assertThatThrownBy(() -> {
            User ignored = noPending.promotePendingEmail(NOW);
            assertThat(ignored).isNotNull();
        }).isInstanceOf(DomainException.class);

        User hasEmail = reconstructUser(Email.create(new ErrorCollector(), EMAIL), PASSWORD_HASH, false,
                AUTH_PROVIDERS, null, Email.create(new ErrorCollector(), "pending@keirekipro.click"));
        assertThatThrownBy(() -> {
            User ignored = hasEmail.promotePendingEmail(NOW);
            assertThat(ignored).isNotNull();
        }).isInstanceOf(DomainException.class);
    }

    @Test
    @DisplayName("確認前のアカウントの delete は UserDeletedEvent を積まない")
    void test39() {
        User unverified = reconstructUser(Email.create(new ErrorCollector(), EMAIL), PASSWORD_HASH, false,
                AUTH_PROVIDERS, null, null);
        unverified.delete();
        assertThat(unverified.getDomainEvents()).isEmpty();

        // 設定待ちのメールアドレスだけを持つアカウントも積まない
        User pendingOnly = reconstructUser(null, PASSWORD_HASH, false, AUTH_PROVIDERS, null,
                Email.create(new ErrorCollector(), "pending@keirekipro.click"));
        pendingOnly.delete();
        assertThat(pendingOnly.getDomainEvents()).isEmpty();
    }

    @Test
    @DisplayName("確認前のアカウントの2段階認証の有効化を断る")
    void test40() {
        when(errorCollector.hasErrors()).thenReturn(true);

        // 確認前のメールアドレスとパスワードを持つ
        User unverified = reconstructUser(Email.create(new ErrorCollector(), EMAIL), PASSWORD_HASH, false,
                AUTH_PROVIDERS, null, null);
        assertThatThrownBy(() -> {
            User ignored = unverified.changeTwoFactorAuthEnabled(errorCollector, true);
            assertThat(ignored).isNotNull();
        }).isInstanceOf(DomainException.class);

        // 設定待ちのメールアドレスとパスワードを持つ
        User pendingOnly = reconstructUser(null, PASSWORD_HASH, false, AUTH_PROVIDERS, null,
                Email.create(new ErrorCollector(), "pending@keirekipro.click"));
        assertThatThrownBy(() -> {
            User ignored = pendingOnly.changeTwoFactorAuthEnabled(errorCollector, true);
            assertThat(ignored).isNotNull();
        }).isInstanceOf(DomainException.class);

        verify(errorCollector, times(2)).addError(eq("twoFactorAuthEnabled"),
                eq("メールアドレスとパスワードが未設定の場合は二段階認証を有効にできません。"));
    }

    @Test
    @DisplayName("確認前のアカウントでも2段階認証を無効にできる")
    void test41() {
        User unverified = reconstructUser(Email.create(new ErrorCollector(), EMAIL), PASSWORD_HASH, true,
                AUTH_PROVIDERS, null, null);

        User updated = unverified.changeTwoFactorAuthEnabled(errorCollector, false);

        assertThat(updated.isTwoFactorAuthEnabled()).isFalse();
        verify(errorCollector, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("2段階認証が有効なまま確認前のアカウントを再構築できる")
    void test42() {
        User user = reconstructUser(Email.create(new ErrorCollector(), EMAIL), PASSWORD_HASH, true,
                AUTH_PROVIDERS, null, null);

        assertThat(user.isTwoFactorAuthEnabled()).isTrue();
        assertThat(user.isEmailVerified()).isFalse();
    }

    @Test
    @DisplayName("確認前のアカウントで外部連携が1つのときに解除を断る")
    void test43() {
        when(errorCollector.hasErrors()).thenReturn(true);

        // 確認前のメールアドレスとパスワードを持つ
        User unverified = reconstructUser(Email.create(new ErrorCollector(), EMAIL), PASSWORD_HASH, false,
                AUTH_PROVIDERS, null, null);
        assertThatThrownBy(() -> {
            User ignored = unverified.removeAuthProvider(errorCollector, "google");
            assertThat(ignored).isNotNull();
        }).isInstanceOf(DomainException.class);

        // 設定待ちのメールアドレスとパスワードを持つ
        User pendingOnly = reconstructUser(null, PASSWORD_HASH, false, AUTH_PROVIDERS, null,
                Email.create(new ErrorCollector(), "pending@keirekipro.click"));
        assertThatThrownBy(() -> {
            User ignored = pendingOnly.removeAuthProvider(errorCollector, "google");
            assertThat(ignored).isNotNull();
        }).isInstanceOf(DomainException.class);

        verify(errorCollector, times(2)).addError(eq("authProviders"),
                eq("メールアドレスとパスワードが設定済みでないと、連携を解除できません。"));
    }

    @Test
    @DisplayName("確認前のアカウントでも外部連携が2つあれば1つを解除できる")
    void test44() {
        Map<String, AuthProvider> providers = new HashMap<>();
        providers.put("google", AuthProvider.create(new ErrorCollector(), "google", "googleId"));
        providers.put("github", AuthProvider.create(new ErrorCollector(), "github", "githubId"));
        User unverified = reconstructUser(Email.create(new ErrorCollector(), EMAIL), PASSWORD_HASH, false,
                providers, null, null);

        User updated = unverified.removeAuthProvider(errorCollector, "google");

        assertThat(updated.getAuthProviders()).containsOnlyKeys("github");
        verify(errorCollector, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("ユーザーを変える操作のあとも emailVerifiedAt と pendingEmail を引き継ぐ")
    void test45() {
        Email pending = Email.create(new ErrorCollector(), "pending@keirekipro.click");
        User user = reconstructUser(null, PASSWORD_HASH, false, AUTH_PROVIDERS, EMAIL_VERIFIED_AT, pending);

        User updated = user.changeUsername(new ErrorCollector(), "renamed")
                .changeProfileImage("profile/renamed.jpg")
                .resetPassword("newHash");

        assertThat(updated.getEmailVerifiedAt()).isEqualTo(EMAIL_VERIFIED_AT);
        assertThat(updated.getPendingEmail()).isEqualTo(pending);
    }

    private static User reconstructUser(Email email,
            String passwordHash,
            boolean twoFactorAuthEnabled,
            Map<String, AuthProvider> authProviders,
            LocalDateTime emailVerifiedAt,
            Email pendingEmail) {
        return User.reconstruct(
                ID,
                email,
                passwordHash,
                twoFactorAuthEnabled,
                authProviders,
                EnumSet.of(RoleName.USER),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT,
                emailVerifiedAt,
                pendingEmail);
    }
}
