package com.example.keirekipro.unit.usecase.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.io.IOException;
import java.time.LocalDateTime;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.AuthProvider;
import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.infrastructure.shared.aws.AwsS3Client;
import com.example.keirekipro.shared.Notification;
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
    private UserRepository userRepository;

    @Mock
    private AwsS3Client awsS3Client;

    @InjectMocks
    private GetUserInfoUseCase getUserInfoUseCase;

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME_VALUE = "test-user";
    private static final String PROFILE_IMAGE_PATH = "profile/test-user.jpg";
    private static final String PROVIDER_TYPE_VALUE = "google";
    private static final String PROVIDER_USER_ID_VALUE = "109876543210987654321";
    private static final LocalDateTime CREATED_AT = LocalDateTime.now();
    private static final LocalDateTime UPDATED_AT = LocalDateTime.now();

    @Test
    @DisplayName("正常にユーザー情報取得ができる")
    void test1() throws IOException {
        // ユーザー情報を準備
        Notification notification = new Notification();
        AuthProvider authProvider = AuthProvider.create(notification, PROVIDER_TYPE_VALUE, PROVIDER_USER_ID_VALUE);
        User user = User.reconstruct(
                USER_ID,
                1,
                Email.create(notification, EMAIL),
                null,
                false,
                Map.of(PROVIDER_TYPE_VALUE.toLowerCase(), authProvider),
                PROFILE_IMAGE_PATH,
                USERNAME_VALUE,
                CREATED_AT,
                UPDATED_AT);
        byte[] profileImageData = new byte[] { 0x12, 0x34, 0x56 };

        // モックをセットアップ
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        when(awsS3Client.getFileAsBytes(PROFILE_IMAGE_PATH)).thenReturn(profileImageData);

        // ユースケース実行
        GetUserInfoUseCaseDto result = getUserInfoUseCase.execute(USER_ID);

        // 検証
        assertThat(result).isNotNull();
        assertThat(result.getId()).isEqualTo(USER_ID);
        assertThat(result.getEmail()).isEqualTo(EMAIL);
        assertThat(result.getUsername()).isEqualTo(USERNAME_VALUE);
        assertThat(result.getProfileImage()).isEqualTo(profileImageData);
        assertThat(result.isTwoFactorAuthEnabled()).isFalse();
        assertThat(result.getAuthProviders()).hasSize(1);
        assertThat(result.getAuthProviders().get(0).getProviderType()).isEqualTo(PROVIDER_TYPE_VALUE);
        assertThat(result.getAuthProviders().get(0).getProviderUserId()).isEqualTo(PROVIDER_USER_ID_VALUE);

        verify(awsS3Client).getFileAsBytes(PROFILE_IMAGE_PATH);
    }

    @Test
    @DisplayName("プロフィール画像がnullの場合、S3へのプロフィール画像取得が行われない")
    void test2() throws IOException {
        // プロフィール画像がnullのユーザー情報を準備
        Notification notification = new Notification();
        AuthProvider authProvider = AuthProvider.create(notification, PROVIDER_TYPE_VALUE, PROVIDER_USER_ID_VALUE);
        User user = User.reconstruct(
                USER_ID,
                1,
                Email.create(notification, EMAIL),
                null,
                false,
                Map.of(PROVIDER_TYPE_VALUE.toLowerCase(), authProvider),
                null,
                USERNAME_VALUE,
                CREATED_AT,
                UPDATED_AT);

        // モックをセットアップ
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));

        // ユースケース実行
        GetUserInfoUseCaseDto result = getUserInfoUseCase.execute(USER_ID);

        // 検証
        assertThat(result.getProfileImage()).isNull();
        verify(awsS3Client, never()).getFileAsBytes(anyString());
    }

    @Test
    @DisplayName("ユーザー情報が存在しない場合、AccessDeniedExceptionがスローされる")
    void test3() throws Exception {
        // モックをセットアップ
        when(userRepository.findById(USER_ID)).thenReturn(Optional.empty());

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
        Notification notification = new Notification();
        AuthProvider authProvider = AuthProvider.create(notification, PROVIDER_TYPE_VALUE, PROVIDER_USER_ID_VALUE);
        User user = User.reconstruct(
                USER_ID,
                1,
                Email.create(notification, EMAIL),
                null,
                false,
                Map.of(PROVIDER_TYPE_VALUE.toLowerCase(), authProvider),
                PROFILE_IMAGE_PATH,
                USERNAME_VALUE,
                CREATED_AT,
                UPDATED_AT);

        // モックをセットアップ
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        when(awsS3Client.getFileAsBytes(PROFILE_IMAGE_PATH)).thenThrow(new IOException("S3 error"));

        // ユースケース実行（内部でIOExceptionはキャッチされ、profileImageはnullになる）
        GetUserInfoUseCaseDto result = getUserInfoUseCase.execute(USER_ID);

        // 検証
        assertThat(result.getProfileImage()).isNull();
        verify(awsS3Client).getFileAsBytes(PROFILE_IMAGE_PATH);
    }
}
