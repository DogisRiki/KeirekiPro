package com.example.keirekipro.unit.domain.model.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

import java.util.Arrays;
import java.util.List;

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

    @Test
    @DisplayName("有効な値でインスタンス化する")
    void test1() {
        AuthProvider provider = AuthProvider.create(notification, "Google", "gid‑123");

        assertThat(provider).isNotNull();
        assertThat(provider.getProviderName()).isEqualTo("google");
        assertThat(provider.getProviderUserId()).isEqualTo("gid‑123");
        verify(notification, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("プロバイダー名が空の場合にエラーが登録される")
    void test2() {
        List<String> testValues = Arrays.asList("", "  ", null);

        for (String value : testValues) {
            // 毎回モックをリセットして、呼び出し履歴をクリアする
            reset(notification);
            AuthProvider provider = AuthProvider.create(notification, value, "uid‑1");

            assertThat(provider).isNotNull();
            // プロバイダー名に対するエラーメッセージが登録される
            verify(notification, times(1)).addError(
                    eq("providerName"),
                    eq("プロバイダータイプが空です。"));
        }
    }

    @Test
    @DisplayName("許可されていないプロバイダー名の場合にエラーが登録される")
    void test3() {
        List<String> invalidNames = List.of("twitter", "FACEBOOK", "example");

        for (String name : invalidNames) {
            reset(notification);
            AuthProvider provider = AuthProvider.create(notification, name, "uid‑2");

            assertThat(provider).isNotNull();
            // プロバイダー名に対するエラーメッセージが登録される
            verify(notification, times(1)).addError(
                    eq("providerName"),
                    eq("許可されていないプロバイダー名です。"));
        }
    }

    @Test
    @DisplayName("プロバイダー側ユーザーIDが空の場合にエラーが登録される")
    void test4() {
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
