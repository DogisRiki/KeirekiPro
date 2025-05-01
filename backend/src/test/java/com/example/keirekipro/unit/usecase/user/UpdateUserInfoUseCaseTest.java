package com.example.keirekipro.unit.usecase.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mockStatic;
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
import com.example.keirekipro.presentation.user.dto.UpdateUserInfoRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.shared.utils.FileUtil;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;
import com.example.keirekipro.usecase.user.UpdateUserInfoUseCase;
import com.example.keirekipro.usecase.user.dto.UpdateUserInfoUseCaseDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockedStatic;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.multipart.MultipartFile;

@ExtendWith(MockitoExtension.class)
class UpdateUserInfoUseCaseTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private AwsS3Client awsS3Client;

    @InjectMocks
    private UpdateUserInfoUseCase updateUserInfoUseCase;

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");

    // ダミーのPNG(実際には中身不十分だが、FileUtilはモックするので問題なし)
    private static final byte[] PROFILE_IMAGE_BYTES = new byte[] {
            (byte) 0x89, 0x50, 0x4E, 0x47,
            0x0D, 0x0A, 0x1A, 0x0A
    };

    private static final MockMultipartFile PROFILE_IMAGE = new MockMultipartFile(
            "profileImage",
            "test.png",
            "image/png",
            PROFILE_IMAGE_BYTES);

    @Test
    @DisplayName("正常にユーザー情報更新ができる")
    void test1() throws IOException {
        // 準備
        UpdateUserInfoRequest request = new UpdateUserInfoRequest();
        request.setUsername("Valid User");
        request.setProfileImage(PROFILE_IMAGE);
        request.setTwoFactorAuthEnabled(true);

        Notification notification = new Notification();
        AuthProvider authProvider = AuthProvider.create(notification, "google", "gid-1");
        User existingUser = User.reconstruct(
                USER_ID,
                1,
                Email.create(notification, "test@example.com"),
                "passowrd",
                false,
                Map.of("google", authProvider),
                null,
                "old",
                LocalDateTime.now(),
                LocalDateTime.now());

        // モックをセットアップ
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(existingUser));
        when(awsS3Client.uploadFile(any(MultipartFile.class), eq("/profile/image/")))
                .thenReturn("s3-key");

        // FileUtilのメソッドはすべてtrueを返すようモック
        try (MockedStatic<FileUtil> fileUtilMock = mockStatic(FileUtil.class)) {
            fileUtilMock.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(true);
            fileUtilMock.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(true);
            fileUtilMock.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(true);
            fileUtilMock.when(() -> FileUtil.isImageReadValid(any())).thenReturn(true);

            // ユースケース実行
            UpdateUserInfoUseCaseDto result = updateUserInfoUseCase.execute(request, USER_ID);

            // 検証
            assertThat(result).isNotNull();
            assertThat(result.getId()).isEqualTo(USER_ID);

            ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
            verify(userRepository).save(captor.capture());
            User savedUser = captor.getValue();

            assertThat(savedUser.getUsername()).isEqualTo("Valid User");
            assertThat(savedUser.isTwoFactorAuthEnabled()).isTrue();
            assertThat(savedUser.getProfileImage()).isEqualTo("s3-key");

            assertThat(result.getUsername()).isEqualTo(savedUser.getUsername());
            assertThat(result.isTwoFactorAuthEnabled()).isEqualTo(savedUser.isTwoFactorAuthEnabled());
            assertThat(result.getProfileImage()).isEqualTo(PROFILE_IMAGE_BYTES);

            verify(awsS3Client).uploadFile(PROFILE_IMAGE, "/profile/image/");
        }
    }

    @Test
    @DisplayName("許可されていないMIMEタイプの場合はUseCaseExceptionがスローされる")
    void test2() throws Exception {
        // 準備
        MockMultipartFile invalidFile = new MockMultipartFile(
                "profileImage",
                "test.png",
                "text/plain", // MIMEタイプが不正
                PROFILE_IMAGE_BYTES);

        UpdateUserInfoRequest request = new UpdateUserInfoRequest();
        request.setUsername("Test User");
        request.setProfileImage(invalidFile);
        request.setTwoFactorAuthEnabled(false);

        // isMimeTypeValidだけfalseにする
        try (MockedStatic<FileUtil> fileUtilMock = mockStatic(FileUtil.class)) {
            fileUtilMock.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(false);
            fileUtilMock.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(true);
            fileUtilMock.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(true);
            fileUtilMock.when(() -> FileUtil.isImageReadValid(any())).thenReturn(true);

            // ユースケース実行
            assertThatThrownBy(() -> updateUserInfoUseCase.execute(request, USER_ID))
                    .isInstanceOf(UseCaseException.class)
                    .matches(e -> ((UseCaseException) e).getErrors().containsKey("profileImage"));

            verify(awsS3Client, never()).uploadFile(any(MultipartFile.class), any(String.class));
            verify(userRepository, never()).save(any());
        }
    }

    @Test
    @DisplayName("許可されていない拡張子の場合はUseCaseExceptionがスローされる")
    void test3() throws Exception {
        // 準備
        MockMultipartFile invalidFile = new MockMultipartFile(
                "profileImage",
                "test.txt", // 拡張子不正
                "image/png", // MIMEタイプはOKでも拡張子NG
                PROFILE_IMAGE_BYTES);

        UpdateUserInfoRequest request = new UpdateUserInfoRequest();
        request.setUsername("Test User");
        request.setProfileImage(invalidFile);
        request.setTwoFactorAuthEnabled(false);

        // isExtensionValidだけfalseにする
        try (MockedStatic<FileUtil> fileUtilMock = mockStatic(FileUtil.class)) {
            fileUtilMock.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(true);
            fileUtilMock.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(false);
            fileUtilMock.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(true);
            fileUtilMock.when(() -> FileUtil.isImageReadValid(any())).thenReturn(true);

            // ユースケース実行
            assertThatThrownBy(() -> updateUserInfoUseCase.execute(request, USER_ID))
                    .isInstanceOf(UseCaseException.class)
                    .matches(e -> ((UseCaseException) e).getErrors().containsKey("profileImage"));

            verify(awsS3Client, never()).uploadFile(any(MultipartFile.class), any(String.class));
            verify(userRepository, never()).save(any());
        }
    }

    @Test
    @DisplayName("ファイルサイズ超過の場合はUseCaseExceptionがスローされる")
    void test4() throws Exception {
        // 準備
        MockMultipartFile tooLargeFile = new MockMultipartFile(
                "profileImage",
                "test.png",
                "image/png",
                new byte[1024 * 1024 + 1] // 1MB超え
        );

        UpdateUserInfoRequest request = new UpdateUserInfoRequest();
        request.setUsername("Test User");
        request.setProfileImage(tooLargeFile);
        request.setTwoFactorAuthEnabled(false);

        // isFileSizeValidだけfalseにする
        try (MockedStatic<FileUtil> fileUtilMock = mockStatic(FileUtil.class)) {
            fileUtilMock.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(true);
            fileUtilMock.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(true);
            fileUtilMock.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(false);
            fileUtilMock.when(() -> FileUtil.isImageReadValid(any())).thenReturn(true);

            // ユースケース実行
            assertThatThrownBy(() -> updateUserInfoUseCase.execute(request, USER_ID))
                    .isInstanceOf(UseCaseException.class)
                    .matches(e -> ((UseCaseException) e).getErrors().containsKey("profileImage"));

            verify(awsS3Client, never()).uploadFile(any(MultipartFile.class), any(String.class));
            verify(userRepository, never()).save(any());
        }
    }

    @Test
    @DisplayName("無効な画像ファイルの場合はUseCaseExceptionがスローされる")
    void test5() throws Exception {
        // 準備
        MockMultipartFile invalidFile = new MockMultipartFile(
                "profileImage",
                "test.png",
                "image/png",
                "dummy".getBytes());

        UpdateUserInfoRequest request = new UpdateUserInfoRequest();
        request.setUsername("Test User");
        request.setProfileImage(invalidFile);
        request.setTwoFactorAuthEnabled(false);

        // isImageReadValidだけfalseにする
        try (MockedStatic<FileUtil> fileUtilMock = mockStatic(FileUtil.class)) {
            fileUtilMock.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(true);
            fileUtilMock.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(true);
            fileUtilMock.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(true);
            fileUtilMock.when(() -> FileUtil.isImageReadValid(any())).thenReturn(false);

            // ユースケース実行
            assertThatThrownBy(() -> updateUserInfoUseCase.execute(request, USER_ID))
                    .isInstanceOf(UseCaseException.class)
                    .matches(e -> ((UseCaseException) e).getErrors().containsKey("profileImage"));

            verify(awsS3Client, never()).uploadFile(any(MultipartFile.class), any(String.class));
            verify(userRepository, never()).save(any());
        }
    }

    @Test
    @DisplayName("S3へのアップロードに失敗した場合、UseCaseExceptionがスローされる")
    void test6() throws IOException {
        // 準備
        UpdateUserInfoRequest request = new UpdateUserInfoRequest();
        request.setUsername("Valid User");
        request.setProfileImage(PROFILE_IMAGE);
        request.setTwoFactorAuthEnabled(true);

        Notification notification = new Notification();
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(
                User.reconstruct(USER_ID, 1, Email.create(notification, "test@example.com"), "dummy-password-hash",
                        false, Map.of(), null, "", LocalDateTime.now(),
                        LocalDateTime.now())));

        // FileUtil側は全部OKにする(ここはアップロードで失敗を再現したいのでバリデーションは通す)
        try (MockedStatic<FileUtil> fileUtilMock = mockStatic(FileUtil.class)) {
            fileUtilMock.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(true);
            fileUtilMock.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(true);
            fileUtilMock.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(true);
            fileUtilMock.when(() -> FileUtil.isImageReadValid(any())).thenReturn(true);

            // モックをセットアップ
            when(awsS3Client.uploadFile(eq(PROFILE_IMAGE), eq("/profile/image/")))
                    .thenThrow(new IOException("S3 error"));

            // ユースケース実行
            assertThatThrownBy(() -> updateUserInfoUseCase.execute(request, USER_ID))
                    .isInstanceOf(UseCaseException.class)
                    .hasMessage("プロフィール画像のアップロードに失敗しました。しばらく時間を置いてから再度お試しください。");

            verify(userRepository, never()).save(any());
        }
    }

    @Test
    @DisplayName("ユーザーが存在しない場合、AccessDeniedExceptionがスローされる")
    void test7() throws IOException {
        // 準備
        UpdateUserInfoRequest request = new UpdateUserInfoRequest();
        request.setUsername("Valid User");
        request.setProfileImage(PROFILE_IMAGE);
        request.setTwoFactorAuthEnabled(true);

        when(userRepository.findById(USER_ID)).thenReturn(Optional.empty());

        // FileUtilは全部trueを返す
        try (MockedStatic<FileUtil> fileUtilMock = mockStatic(FileUtil.class)) {
            fileUtilMock.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(true);
            fileUtilMock.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(true);
            fileUtilMock.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(true);
            fileUtilMock.when(() -> FileUtil.isImageReadValid(any())).thenReturn(true);

            // ユースケース実行
            assertThatThrownBy(() -> updateUserInfoUseCase.execute(request, USER_ID))
                    .isInstanceOf(AccessDeniedException.class)
                    .hasMessage("不正なアクセスです。");

            verify(userRepository, never()).save(any());
        }
    }
}
