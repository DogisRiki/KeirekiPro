package com.example.keirekipro.unit.usecase.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.io.IOException;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.infrastructure.repository.user.dto.UserInfo;
import com.example.keirekipro.infrastructure.repository.user.dto.UserInfo.AuthProviderInfo;
import com.example.keirekipro.infrastructure.repository.user.mapper.UserMapper;
import com.example.keirekipro.infrastructure.shared.aws.AwsS3Client;
import com.example.keirekipro.usecase.user.GetUserInfoUseCase;
import com.example.keirekipro.usecase.user.dto.GetUserInfoUseCaseDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.access.AccessDeniedException;

@ExtendWith(MockitoExtension.class)
class GetUserInfoUseCaseTest {

    @Mock
    private UserMapper userMapper;

    @Mock
    private AwsS3Client awsS3Client;

    @InjectMocks
    private GetUserInfoUseCase getUserInfoUseCase;

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME = "test-user";
    private static final String PROFILE_IMAGE = "profile/test-user.jpg";
    private static final UUID AUTH_PROVIDER_ID = UUID.fromString("f47ac10b-58cc-4372-a567-0e02b2c3d479");
    private static final String PROVIDER_TYPE = "GOOGLE";
    private static final String PROVIDER_USER_ID = "109876543210987654321";

    @Test
    @DisplayName("正常にユーザー情報取得ができる")
    void test1() throws IOException {
        // ユーザー情報を準備
        AuthProviderInfo authProviderInfo = new AuthProviderInfo(AUTH_PROVIDER_ID, PROVIDER_TYPE, PROVIDER_USER_ID);
        UserInfo userInfo = new UserInfo(USER_ID, EMAIL, USERNAME, PROFILE_IMAGE, false, List.of(authProviderInfo));
        byte[] profileImageData = new byte[] { 0x12, 0x34, 0x56 };

        // モックをセットアップ
        when(userMapper.selectById(USER_ID)).thenReturn(Optional.of(userInfo));
        when(awsS3Client.getFileAsBytes(PROFILE_IMAGE)).thenReturn(profileImageData);

        // ユースケース実行
        GetUserInfoUseCaseDto result = getUserInfoUseCase.execute(USER_ID);

        // 検証
        assertThat(result).isNotNull();
        assertThat(result.getId()).isEqualTo(USER_ID);
        assertThat(result.getEmail()).isEqualTo(EMAIL);
        assertThat(result.getUsername()).isEqualTo(USERNAME);
        assertThat(result.getProfileImage()).isEqualTo(profileImageData);
        assertThat(result.isTwoFactorAuthEnabled()).isFalse();
        assertThat(result.getAuthProviders()).hasSize(1);
        assertThat(result.getAuthProviders().get(0).getId()).isEqualTo(AUTH_PROVIDER_ID);
        assertThat(result.getAuthProviders().get(0).getProviderType()).isEqualTo(PROVIDER_TYPE);
        assertThat(result.getAuthProviders().get(0).getProviderUserId()).isEqualTo(PROVIDER_USER_ID);

        verify(awsS3Client).getFileAsBytes(eq(userInfo.getProfileImage()));
    }

    @Test
    @DisplayName("プロフィール画像がnullの場合、S3へのプロフィール画像取得が行われない")
    void test2() throws IOException {
        // プロフィール画像がnullのユーザー情報を準備
        AuthProviderInfo authProviderInfo = new AuthProviderInfo(AUTH_PROVIDER_ID, PROVIDER_TYPE, PROVIDER_USER_ID);
        UserInfo userInfo = new UserInfo(USER_ID, EMAIL, USERNAME, null, false, List.of(authProviderInfo));

        // モックをセットアップ
        when(userMapper.selectById(USER_ID)).thenReturn(Optional.of(userInfo));

        // ユースケース実行
        GetUserInfoUseCaseDto result = getUserInfoUseCase.execute(USER_ID);

        // 検証
        assertThat(result.getProfileImage()).isNull();
        verify(awsS3Client, never()).getFileAsBytes(anyString());
    }

    @Test
    @DisplayName("ユーザー情報が存在しない場合、AccessDeniedExceptionがスローされる")
    void test3() throws IOException {
        // モックをセットアップ
        when(userMapper.selectById(USER_ID)).thenReturn(Optional.empty());

        // ユースケース実行
        assertThatThrownBy(() -> getUserInfoUseCase.execute(USER_ID))
                .isInstanceOf(AccessDeniedException.class)
                .hasMessage("不正なアクセスです。");

        // 検証
        verify(awsS3Client, never()).getFileAsBytes(anyString());
    }

    @Test
    @DisplayName("S3からプロフィール画像を取得できない場合、IOExceptionがスローされるが処理が継続される")
    void test4() throws IOException {
        // プロフィール画像が設定されているユーザー情報を準備
        AuthProviderInfo authProviderInfo = new AuthProviderInfo(AUTH_PROVIDER_ID, PROVIDER_TYPE, PROVIDER_USER_ID);
        UserInfo userInfo = new UserInfo(USER_ID, EMAIL, USERNAME, PROFILE_IMAGE, false, List.of(authProviderInfo));

        // モックをセットアップ
        when(userMapper.selectById(USER_ID)).thenReturn(Optional.of(userInfo));
        when(awsS3Client.getFileAsBytes(PROFILE_IMAGE)).thenThrow(new IOException("S3 error"));

        // ユースケース実行（内部でIOExceptionはキャッチされ、profileImageはnullになる）
        GetUserInfoUseCaseDto result = getUserInfoUseCase.execute(USER_ID);

        // 検証
        assertThat(result.getProfileImage()).isNull();
        verify(awsS3Client).getFileAsBytes(eq(PROFILE_IMAGE));
    }
}
