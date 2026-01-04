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
                USERNAME)).isInstanceOf(DomainException.class)
                .hasMessageContaining("ユーザー情報の作成に失敗しました。");
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
                UPDATED_AT);

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
                UPDATED_AT);

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
                UPDATED_AT);

        // DomainExceptionがスローされる
        assertThatThrownBy(
                () -> user.setEmail(errorCollector, Email.create(errorCollector, "other@keirekipro.click")))
                .isInstanceOf(DomainException.class);

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
                UPDATED_AT);

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
                UPDATED_AT);

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> user.changePassword(errorCollector, PASSWORD_HASH))
                .isInstanceOf(DomainException.class);

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
                UPDATED_AT);

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
                UPDATED_AT);

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
                UPDATED_AT);

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> user1.changeTwoFactorAuthEnabled(errorCollector, true))
                .isInstanceOf(DomainException.class);

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
                UPDATED_AT);

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> user2.changeTwoFactorAuthEnabled(errorCollector, true))
                .isInstanceOf(DomainException.class);

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
                UPDATED_AT);

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
                UPDATED_AT);

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
                UPDATED_AT);

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> user.removeAuthProvider(errorCollector, "github")).isInstanceOf(DomainException.class);

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
                UPDATED_AT);

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> user.removeAuthProvider(errorCollector, "google")).isInstanceOf(DomainException.class);

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
                UPDATED_AT);

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
                UPDATED_AT);

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
                UPDATED_AT);

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> user.changeUsername(errorCollector, " "))
                .isInstanceOf(DomainException.class);

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
                UPDATED_AT);

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
                UPDATED_AT);

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
                UPDATED_AT);

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
                UPDATED_AT);

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
                UPDATED_AT);

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
                UPDATED_AT);

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> user.addRole(errorCollector, RoleName.ADMIN))
                .isInstanceOf(DomainException.class);

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
                UPDATED_AT);

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
                UPDATED_AT);

        // DomainExceptionがスローされる
        assertThatThrownBy(() -> user.changeTwoFactorAuthEnabled(errorCollector, false))
                .isInstanceOf(DomainException.class);

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
                UPDATED_AT)).isInstanceOf(DomainException.class)
                .hasMessageContaining("管理者の場合は二段階認証が必須です。");
    }
}
