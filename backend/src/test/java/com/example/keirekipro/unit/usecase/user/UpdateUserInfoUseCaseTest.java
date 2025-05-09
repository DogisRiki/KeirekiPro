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
import java.time.Duration;
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

    // ダミーのPNGヘッダバイト列
    private static final byte[] PROFILE_IMAGE_BYTES = new byte[] {
            (byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
    };
    private static final MockMultipartFile PROFILE_IMAGE = new MockMultipartFile("profileImage", "test.png",
            "image/png", PROFILE_IMAGE_BYTES);

    // uploadFile の戻り値（S3キー）と generatePresignedUrl の戻り値（署名付きURL）
    private static final String S3_KEY = "s3-key";
    private static final String SIGNED_URL = "https://signed.example.com/profile/test.png";

    @Test
    @DisplayName("正常にユーザー情報更新ができる")
    void test1() throws IOException {
        // リクエスト準備
        UpdateUserInfoRequest request = new UpdateUserInfoRequest();
        request.setUsername("Valid User");
        request.setProfileImage(PROFILE_IMAGE);
        request.setTwoFactorAuthEnabled(true);

        // 既存ユーザー
        Notification notification = new Notification();
        AuthProvider authProvider = AuthProvider.create(notification, "google", "gid-1");
        User existingUser = User.reconstruct(
                USER_ID, 1,
                Email.create(notification, "test@example.com"),
                "dummy-password", false,
                Map.of("google", authProvider),
                null, "old-name",
                LocalDateTime.now(), LocalDateTime.now());

        // S3 とリポジトリのモック
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(existingUser));
        when(awsS3Client.uploadFile(any(MultipartFile.class), eq("/profile/image/")))
                .thenReturn(S3_KEY);
        when(awsS3Client.generatePresignedUrl(eq(S3_KEY), eq(Duration.ofMinutes(10))))
                .thenReturn(SIGNED_URL);

        // FileUtil のバリデーションをすべて通過させる
        try (MockedStatic<FileUtil> util = mockStatic(FileUtil.class)) {
            util.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(true);
            util.when(() -> FileUtil.isImageReadValid(any())).thenReturn(true);

            // 実行
            UpdateUserInfoUseCaseDto result = updateUserInfoUseCase.execute(request, USER_ID);

            // 保存された User の検証
            ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
            verify(userRepository).save(captor.capture());
            User saved = captor.getValue();
            assertThat(saved.getUsername()).isEqualTo("Valid User");
            assertThat(saved.isTwoFactorAuthEnabled()).isTrue();
            assertThat(saved.getProfileImage()).isEqualTo(S3_KEY);

            // 戻り値 DTO の検証
            assertThat(result.getId()).isEqualTo(USER_ID);
            assertThat(result.getUsername()).isEqualTo("Valid User");
            assertThat(result.isTwoFactorAuthEnabled()).isTrue();
            assertThat(result.getProfileImage()).isEqualTo(SIGNED_URL);

            verify(awsS3Client).uploadFile(PROFILE_IMAGE, "/profile/image/");
            verify(awsS3Client).generatePresignedUrl(S3_KEY, Duration.ofMinutes(10));
        }
    }

    @Test
    @DisplayName("許可されていないMIMEタイプの場合はUseCaseExceptionがスローされる")
    void test2() throws Exception {
        MockMultipartFile badFile = new MockMultipartFile(
                "profileImage", "test.png", "text/plain", PROFILE_IMAGE_BYTES);

        UpdateUserInfoRequest req = new UpdateUserInfoRequest();
        req.setUsername("User");
        req.setProfileImage(badFile);
        req.setTwoFactorAuthEnabled(false);

        try (MockedStatic<FileUtil> util = mockStatic(FileUtil.class)) {
            util.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(false);
            util.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(true);
            util.when(() -> FileUtil.isImageReadValid(any())).thenReturn(true);

            assertThatThrownBy(() -> updateUserInfoUseCase.execute(req, USER_ID))
                    .isInstanceOf(UseCaseException.class)
                    .matches(e -> ((UseCaseException) e).getErrors().containsKey("profileImage"));

            verify(awsS3Client, never()).uploadFile(any(), any());
            verify(userRepository, never()).save(any());
        }
    }

    @Test
    @DisplayName("許可されていない拡張子の場合はUseCaseExceptionがスローされる")
    void test3() throws Exception {
        MockMultipartFile badExt = new MockMultipartFile(
                "profileImage", "test.txt", "image/png", PROFILE_IMAGE_BYTES);

        UpdateUserInfoRequest req = new UpdateUserInfoRequest();
        req.setUsername("User");
        req.setProfileImage(badExt);
        req.setTwoFactorAuthEnabled(false);

        try (MockedStatic<FileUtil> util = mockStatic(FileUtil.class)) {
            util.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(false);
            util.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(true);
            util.when(() -> FileUtil.isImageReadValid(any())).thenReturn(true);

            assertThatThrownBy(() -> updateUserInfoUseCase.execute(req, USER_ID))
                    .isInstanceOf(UseCaseException.class)
                    .matches(e -> ((UseCaseException) e).getErrors().containsKey("profileImage"));

            verify(awsS3Client, never()).uploadFile(any(), any());
            verify(userRepository, never()).save(any());
        }
    }

    @Test
    @DisplayName("ファイルサイズ超過の場合はUseCaseExceptionがスローされる")
    void test4() throws Exception {
        byte[] tooBig = new byte[1024 * 1024 + 1];
        MockMultipartFile bigFile = new MockMultipartFile(
                "profileImage", "test.png", "image/png", tooBig);

        UpdateUserInfoRequest req = new UpdateUserInfoRequest();
        req.setUsername("User");
        req.setProfileImage(bigFile);
        req.setTwoFactorAuthEnabled(false);

        try (MockedStatic<FileUtil> util = mockStatic(FileUtil.class)) {
            util.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(false);
            util.when(() -> FileUtil.isImageReadValid(any())).thenReturn(true);

            assertThatThrownBy(() -> updateUserInfoUseCase.execute(req, USER_ID))
                    .isInstanceOf(UseCaseException.class)
                    .matches(e -> ((UseCaseException) e).getErrors().containsKey("profileImage"));

            verify(awsS3Client, never()).uploadFile(any(), any());
            verify(userRepository, never()).save(any());
        }
    }

    @Test
    @DisplayName("無効な画像ファイルの場合はUseCaseExceptionがスローされる")
    void test5() throws Exception {
        MockMultipartFile badImg = new MockMultipartFile(
                "profileImage", "test.png", "image/png", "dummy".getBytes());

        UpdateUserInfoRequest req = new UpdateUserInfoRequest();
        req.setUsername("User");
        req.setProfileImage(badImg);
        req.setTwoFactorAuthEnabled(false);

        try (MockedStatic<FileUtil> util = mockStatic(FileUtil.class)) {
            util.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(true);
            util.when(() -> FileUtil.isImageReadValid(any())).thenReturn(false);

            assertThatThrownBy(() -> updateUserInfoUseCase.execute(req, USER_ID))
                    .isInstanceOf(UseCaseException.class)
                    .matches(e -> ((UseCaseException) e).getErrors().containsKey("profileImage"));

            verify(awsS3Client, never()).uploadFile(any(), any());
            verify(userRepository, never()).save(any());
        }
    }

    @Test
    @DisplayName("S3へのアップロードに失敗した場合、UseCaseExceptionがスローされる")
    void test6() throws IOException {
        UpdateUserInfoRequest req = new UpdateUserInfoRequest();
        req.setUsername("Valid");
        req.setProfileImage(PROFILE_IMAGE);
        req.setTwoFactorAuthEnabled(true);

        Notification notification = new Notification();
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(
                User.reconstruct(USER_ID, 1, Email.create(notification, "a@b.com"),
                        "pw", false, Map.of(), null, "", LocalDateTime.now(), LocalDateTime.now())));
        try (MockedStatic<FileUtil> util = mockStatic(FileUtil.class)) {
            util.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(true);
            util.when(() -> FileUtil.isImageReadValid(any())).thenReturn(true);

            when(awsS3Client.uploadFile(eq(PROFILE_IMAGE), eq("/profile/image/")))
                    .thenThrow(new IOException("S3 error"));

            assertThatThrownBy(() -> updateUserInfoUseCase.execute(req, USER_ID))
                    .isInstanceOf(UseCaseException.class)
                    .hasMessage("プロフィール画像のアップロードに失敗しました。しばらく時間を置いてから再度お試しください。");

            verify(userRepository, never()).save(any());
        }
    }

    @Test
    @DisplayName("ユーザーが存在しない場合、AccessDeniedExceptionがスローされる")
    void test7() {
        UpdateUserInfoRequest req = new UpdateUserInfoRequest();
        req.setUsername("Valid");
        req.setProfileImage(PROFILE_IMAGE);
        req.setTwoFactorAuthEnabled(true);

        when(userRepository.findById(USER_ID)).thenReturn(Optional.empty());
        try (MockedStatic<FileUtil> util = mockStatic(FileUtil.class)) {
            util.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(true);
            util.when(() -> FileUtil.isImageReadValid(any())).thenReturn(true);

            assertThatThrownBy(() -> updateUserInfoUseCase.execute(req, USER_ID))
                    .isInstanceOf(AccessDeniedException.class)
                    .hasMessage("不正なアクセスです。");

            verify(userRepository, never()).save(any());
        }
    }
}
