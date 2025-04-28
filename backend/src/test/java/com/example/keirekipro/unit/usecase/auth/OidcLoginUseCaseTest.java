package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Collections;
import java.util.Optional;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcUserInfoDto;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.auth.OidcLoginUseCase;
import com.example.keirekipro.usecase.auth.dto.OidcLoginUseCaseDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class OidcLoginUseCaseTest {

    @Mock
    private UserRepository userRepository;

    @InjectMocks
    private OidcLoginUseCase oidcLoginUseCase;

    private static final String PROVIDER_USER_ID = "12345";
    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME = "test-user";
    private static final String PROVIDER_TYPE = "google";

    @Test
    @DisplayName("既存ユーザーの場合(同一または別プロバイダー)、新規ユーザーを作成せず既存ユーザーIDを返す")
    void test1() {
        // モックをセットアップ
        Notification notification = new Notification();
        User existingUser = User.create(
                notification,
                1,
                Email.create(notification, EMAIL),
                null,
                false,
                Collections.emptyMap(),
                null,
                USERNAME);
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(existingUser));

        // ユースケース実行
        OidcLoginUseCaseDto result = oidcLoginUseCase
                .execute(new OidcUserInfoDto(PROVIDER_USER_ID, EMAIL, USERNAME, PROVIDER_TYPE));

        // 検証
        assertThat(result).isNotNull();
        assertThat(result.getId()).isEqualTo(existingUser.getId());
        assertThat(result.getEmail()).isEqualTo(EMAIL);
        assertThat(result.getUsername()).isEqualTo(USERNAME);
        assertThat(result.getProviderType()).isEqualTo(PROVIDER_TYPE);
    }

    @Test
    @DisplayName("未連携かつメールアドレスも既存ユーザーに無い場合、新規ユーザーを作成する")
    void test2() {
        // モックをセットアップ
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());

        // ユースケース実行
        OidcLoginUseCaseDto result = oidcLoginUseCase
                .execute(new OidcUserInfoDto(PROVIDER_USER_ID, EMAIL, USERNAME, PROVIDER_TYPE));

        // 検証
        assertThat(result).isNotNull();
        assertThat(result.getId()).isNotNull(); // idはユースケース内で採番されるためnullチェックのみとする
        assertThat(result.getEmail()).isEqualTo(EMAIL);
        assertThat(result.getUsername()).isEqualTo(USERNAME);
        assertThat(result.getProviderType()).isEqualTo(PROVIDER_TYPE);

        verify(userRepository).save(any(User.class));
    }

    @Test
    @DisplayName("DB登録時に例外が発生した場合、トランザクションがロールバックされる")
    void test3() {
        // モックをセットアップ
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());

        // save時に例外を発生させる
        doThrow(new RuntimeException("登録失敗"))
                .when(userRepository)
                .save(any(User.class));

        // RuntimeExceptionが発生し、トランザクションが中断される
        assertThrows(RuntimeException.class, () -> {
            oidcLoginUseCase.execute(
                    new OidcUserInfoDto(PROVIDER_USER_ID, EMAIL, USERNAME, PROVIDER_TYPE));
        });
    }
}
