package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcUserInfoDto;
import com.example.keirekipro.infrastructure.repository.auth.mapper.UserAuthProviderMapper;
import com.example.keirekipro.infrastructure.repository.user.dto.UserAuthInfoDto;
import com.example.keirekipro.infrastructure.repository.user.mapper.UserMapper;
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
    private UserMapper userMapper;

    @Mock
    private UserAuthProviderMapper userAuthProviderMapper;

    @InjectMocks
    private OidcLoginUseCase oidcLoginUseCase;

    private static final UUID ID = UUID.randomUUID();
    private static final String PROVIDER_USER_ID = "12345";
    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME = "test-user";
    private static final String PASSWORD = "password";
    private static final String PROVIDER_TYPE = "google";

    @Test
    @DisplayName("既存ユーザーの場合(同一または別プロバイダー)、新規ユーザーを作成せず既存ユーザーIDを返す")
    void test1() {
        // モックをセットアップ
        when(userAuthProviderMapper.selectUserIdByProvider(anyString(), anyString())).thenReturn(Optional.of(ID));

        // ユースケース実行
        OidcLoginUseCaseDto result = oidcLoginUseCase
                .execute(new OidcUserInfoDto(PROVIDER_USER_ID, EMAIL, USERNAME, PROVIDER_TYPE));

        // 検証
        assertThat(result).isNotNull();
        assertThat(result.getId()).isEqualTo(ID);
        assertThat(result.getEmail()).isEqualTo(EMAIL);
        assertThat(result.getUsername()).isEqualTo(USERNAME);
        assertThat(result.getProviderType()).isEqualTo(PROVIDER_TYPE);
    }

    @Test
    @DisplayName("未連携かつメールアドレスも既存ユーザーに無い場合、新規ユーザーを作成する")
    void test2() {
        // モックをセットアップ
        when(userAuthProviderMapper.selectUserIdByProvider(anyString(), anyString())).thenReturn(Optional.empty());
        when(userMapper.selectByEmail(anyString())).thenReturn(Optional.empty());

        // ユースケース実行
        OidcLoginUseCaseDto result = oidcLoginUseCase
                .execute(new OidcUserInfoDto(PROVIDER_USER_ID, EMAIL, USERNAME, PROVIDER_TYPE));

        // 検証
        assertThat(result).isNotNull();
        assertThat(result.getId()).isNotNull(); // idはユースケース内で採番されるためnullチェックのみとする
        assertThat(result.getEmail()).isEqualTo(EMAIL);
        assertThat(result.getUsername()).isEqualTo(USERNAME);
        assertThat(result.getProviderType()).isEqualTo(PROVIDER_TYPE);

        verify(userMapper).insert(any(UUID.class), eq(EMAIL), eq(null), eq(USERNAME));
        verify(userAuthProviderMapper).insert(any(UUID.class), any(UUID.class), eq(PROVIDER_TYPE),
                eq(PROVIDER_USER_ID));
    }

    @Test
    @DisplayName("メールアドレスで既存ユーザーが見つかるが、外部連携無しの場合、既存ユーザーに連携情報を追加する")
    void test3() {
        // モックをセットアップ
        when(userAuthProviderMapper.selectUserIdByProvider(anyString(), anyString())).thenReturn(Optional.empty());
        when(userMapper.selectByEmail(anyString()))
                .thenReturn(Optional.of(new UserAuthInfoDto(ID, EMAIL, PASSWORD, false)));

        // ユースケース実行
        OidcLoginUseCaseDto result = oidcLoginUseCase
                .execute(new OidcUserInfoDto(PROVIDER_USER_ID, EMAIL, USERNAME, PROVIDER_TYPE));

        // 検証
        assertThat(result).isNotNull();
        assertThat(result.getId()).isEqualTo(ID);
        assertThat(result.getEmail()).isEqualTo(EMAIL);
        assertThat(result.getUsername()).isEqualTo(USERNAME);
        assertThat(result.getProviderType()).isEqualTo(PROVIDER_TYPE);

        verify(userAuthProviderMapper).insert(any(UUID.class), eq(ID), eq(PROVIDER_TYPE),
                eq(PROVIDER_USER_ID));
    }

    @Test
    @DisplayName("DB登録時に例外が発生した場合、トランザクションがロールバックされる")
    void test4() {
        // モックをセットアップ
        when(userAuthProviderMapper.selectUserIdByProvider(anyString(), anyString())).thenReturn(Optional.empty());
        when(userMapper.selectByEmail(anyString())).thenReturn(Optional.empty());

        // ユーザー登録時に例外を発生させる
        doThrow(new RuntimeException("登録失敗"))
                .when(userMapper)
                .insert(any(UUID.class), anyString(), any(), anyString());

        // RuntimeException が発生し、トランザクションが中断される
        assertThrows(RuntimeException.class, () -> {
            oidcLoginUseCase.execute(
                    new OidcUserInfoDto(PROVIDER_USER_ID, EMAIL, USERNAME, PROVIDER_TYPE));
        });

        // ロールバックされているため、registerAuthProvider()が呼び出されていないことを検証
        verify(userAuthProviderMapper, never())
                .insert(any(UUID.class), any(UUID.class), anyString(), anyString());
    }
}
