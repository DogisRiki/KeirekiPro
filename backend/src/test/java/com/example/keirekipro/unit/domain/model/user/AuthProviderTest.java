package com.example.keirekipro.unit.domain.model.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

import java.time.LocalDateTime;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.AuthProvider;
import com.example.keirekipro.shared.Notification;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class AuthProviderTest {

    @Mock
    private Notification notification;

    private static final String PROVIDER_USER_ID = "123";

    @Test
    @DisplayName("新規構築用コンストラクタでインスタンス化する")
    void test1() {
        AuthProvider provider = AuthProvider.create(notification, "Google", PROVIDER_USER_ID);

        assertThat(provider).isNotNull();
        assertThat(provider.getId()).isNotNull();
        assertThat(provider.getProviderName()).isEqualTo("google");
        assertThat(provider.getProviderUserId()).isEqualTo(PROVIDER_USER_ID);
        assertThat(provider.getCreatedAt()).isNotNull();
        assertThat(provider.getUpdatedAt()).isNotNull();
        verify(notification, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test2() {
        UUID id = UUID.randomUUID();
        LocalDateTime now = LocalDateTime.of(2024, 1, 1, 10, 0);
        AuthProvider provider = AuthProvider.reconstruct(id, "google", PROVIDER_USER_ID, now, now);

        assertThat(provider).isNotNull();
        assertThat(provider.getId()).isEqualTo(id);
        assertThat(provider.getProviderName()).isEqualTo("google");
        assertThat(provider.getProviderUserId()).isEqualTo(PROVIDER_USER_ID);
        assertThat(provider.getCreatedAt()).isEqualTo(now);
        assertThat(provider.getUpdatedAt()).isEqualTo(now);
    }

    @Test
    @DisplayName("プロバイダー名が空の場合にエラーが登録される")
    void test3() {
        List<String> testValues = Arrays.asList("", "  ", null);

        for (String value : testValues) {
            // 毎回モックをリセットして、呼び出し履歴をクリアする
            reset(notification);
            AuthProvider provider = AuthProvider.create(notification, value, PROVIDER_USER_ID);

            assertThat(provider).isNotNull();
            // プロバイダー名に対するエラーメッセージが登録される
            verify(notification, times(1)).addError(
                    eq("providerName"),
                    eq("プロバイダー名が空です。"));
        }
    }

    @Test
    @DisplayName("許可されていないプロバイダー名の場合にエラーが登録される")
    void test4() {
        List<String> invalidNames = List.of("twitter", "FACEBOOK", "example");

        for (String name : invalidNames) {
            reset(notification);
            AuthProvider provider = AuthProvider.create(notification, name, PROVIDER_USER_ID);

            assertThat(provider).isNotNull();
            // プロバイダー名に対するエラーメッセージが登録される
            verify(notification, times(1)).addError(
                    eq("providerName"),
                    eq("許可されていないプロバイダー名です。"));
        }
    }

    @Test
    @DisplayName("プロバイダー側ユーザーIDが空の場合にエラーが登録される")
    void test5() {
        List<String> invalidIds = Arrays.asList("", " ", null);

        for (String pid : invalidIds) {
            reset(notification);
            AuthProvider provider = AuthProvider.create(notification, "github", pid);

            assertThat(provider).isNotNull();
            // ユーザーIDに対するエラーメッセージが登録される
            verify(notification, times(1)).addError(
                    eq("providerUserId"),
                    eq("githubでユーザーIDの取得に失敗しました。"));
        }
    }
}
