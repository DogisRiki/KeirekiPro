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
import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.util.Base64;
import java.util.EnumSet;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.AuthProvider;
import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.RoleName;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.usecase.user.command.UpdateUserInfoCommand;
import com.example.keirekipro.usecase.user.command.UpdateUserInfoCommand.ProfileImageCommand;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.shared.utils.FileUtil;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;
import com.example.keirekipro.usecase.shared.store.ObjectStore;
import com.example.keirekipro.usecase.shared.store.StoredObject;
import com.example.keirekipro.usecase.user.UpdateUserInfoUseCase;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockedStatic;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;
import org.springframework.web.multipart.MultipartFile;

@ExtendWith(MockitoExtension.class)
class UpdateUserInfoUseCaseTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private ObjectStore objectStore;

    @InjectMocks
    private UpdateUserInfoUseCase updateUserInfoUseCase;

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME = "test-user";
    private static final String PASSWORD_HASH = "Password123";

    // ダミーのPNGヘッダバイト列
    private static final byte[] PROFILE_IMAGE_BYTES = Base64.getDecoder()
            .decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=");
    private static final MockMultipartFile PROFILE_IMAGE = new MockMultipartFile("profileImage", "test.png",
            "image/png", PROFILE_IMAGE_BYTES);

    // uploadFile の戻り値（S3キー）
    private static final String S3_KEY = "s3-key";

    @Test
    @DisplayName("正常にユーザー情報更新ができる")
    void test1() throws IOException {
        // リクエスト準備
        UpdateUserInfoCommand request = new UpdateUserInfoCommand(USER_ID, USERNAME, toProfileImage(PROFILE_IMAGE),
                true);

        // 既存ユーザー
        ErrorCollector errorCollector = new ErrorCollector();
        AuthProvider authProvider = AuthProvider.create(errorCollector, "google", "gid-1");
        User existingUser = User.reconstruct(
                USER_ID,
                Email.create(errorCollector, EMAIL),
                PASSWORD_HASH, false,
                Map.of("google", authProvider),
                EnumSet.of(RoleName.USER),
                null,
                "old-name",
                LocalDateTime.now(), LocalDateTime.now());

        // オブジェクトストアとリポジトリのモック
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(existingUser));

        // FileUtil.getExtension()から"png"が返る前提でfileNameを固定
        String expectedFileName = USER_ID.toString() + ".png";
        when(objectStore.putAs(any(StoredObject.class), eq("/profile/image/"), eq(expectedFileName)))
                .thenReturn(S3_KEY);

        // FileUtil のバリデーションをすべて通過させる
        try (MockedStatic<FileUtil> util = mockStatic(FileUtil.class)) {
            util.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(true);
            util.when(() -> FileUtil.isImageReadValid(any())).thenReturn(true);
            util.when(() -> FileUtil.getExtension(any())).thenReturn("png");

            // 実行
            updateUserInfoUseCase.execute(request);

            // 保存されたUserの検証
            ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
            verify(userRepository).save(captor.capture());
            User saved = captor.getValue();

            // 更新対象のデータの検証
            assertThat(saved.getUsername()).isEqualTo(USERNAME);
            assertThat(saved.isTwoFactorAuthEnabled()).isTrue();
            assertThat(saved.getProfileImage()).isEqualTo(S3_KEY);

            // オブジェクトストア呼び出しの検証
            ArgumentCaptor<StoredObject> objectCaptor = ArgumentCaptor.forClass(StoredObject.class);
            ArgumentCaptor<String> fileNameCaptor = ArgumentCaptor.forClass(String.class);
            verify(objectStore).putAs(objectCaptor.capture(), eq("/profile/image/"), fileNameCaptor.capture());

            StoredObject stored = objectCaptor.getValue();
            String actualFileName = fileNameCaptor.getValue();

            assertThat(stored.bytes()).isEqualTo(PROFILE_IMAGE_BYTES);
            assertThat(stored.contentType()).isEqualTo("image/png");

            assertThat(stored.originalFilename()).isEqualTo("test.png");

            // 保存ファイル名が userId + 拡張子 であること
            assertThat(actualFileName).isEqualTo(expectedFileName);
        }
    }

    @Test
    @DisplayName("許可されていないMIMEタイプの場合はUseCaseExceptionがスローされる")
    void test2() throws Exception {
        MockMultipartFile badFile = new MockMultipartFile(
                "profileImage", "test.png", "text/plain", PROFILE_IMAGE_BYTES);

        UpdateUserInfoCommand req = new UpdateUserInfoCommand(USER_ID, "User", toProfileImage(badFile), false);

        try (MockedStatic<FileUtil> util = mockStatic(FileUtil.class)) {
            util.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(false);
            util.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(true);
            util.when(() -> FileUtil.isImageReadValid(any())).thenReturn(true);

            assertThatThrownBy(() -> {
                updateUserInfoUseCase.execute(req);
            }).isInstanceOf(UseCaseException.class)
                    .matches(e -> ((UseCaseException) e).getErrors().containsKey("profileImage"));

            verify(objectStore, never()).putAs(any(), any(), any());
            verify(userRepository, never()).save(any());
        }
    }

    @Test
    @DisplayName("許可されていない拡張子の場合はUseCaseExceptionがスローされる")
    void test3() throws Exception {
        MockMultipartFile badExt = new MockMultipartFile(
                "profileImage", "test.txt", "image/png", PROFILE_IMAGE_BYTES);

        UpdateUserInfoCommand req = new UpdateUserInfoCommand(USER_ID, "User", toProfileImage(badExt), false);

        try (MockedStatic<FileUtil> util = mockStatic(FileUtil.class)) {
            util.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(false);
            util.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(true);
            util.when(() -> FileUtil.isImageReadValid(any())).thenReturn(true);

            assertThatThrownBy(() -> {
                updateUserInfoUseCase.execute(req);
            }).isInstanceOf(UseCaseException.class)
                    .matches(e -> ((UseCaseException) e).getErrors().containsKey("profileImage"));

            verify(objectStore, never()).putAs(any(), any(), any());
            verify(userRepository, never()).save(any());
        }
    }

    @Test
    @DisplayName("ファイルサイズ超過の場合はUseCaseExceptionがスローされる")
    void test4() throws Exception {
        byte[] tooBig = new byte[1024 * 1024 + 1];
        MockMultipartFile bigFile = new MockMultipartFile(
                "profileImage", "test.png", "image/png", tooBig);

        UpdateUserInfoCommand req = new UpdateUserInfoCommand(USER_ID, "User", toProfileImage(bigFile), false);

        try (MockedStatic<FileUtil> util = mockStatic(FileUtil.class)) {
            util.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(false);
            util.when(() -> FileUtil.isImageReadValid(any())).thenReturn(true);

            assertThatThrownBy(() -> {
                updateUserInfoUseCase.execute(req);
            }).isInstanceOf(UseCaseException.class)
                    .matches(e -> ((UseCaseException) e).getErrors().containsKey("profileImage"));

            verify(objectStore, never()).put(any(), any());
            verify(userRepository, never()).save(any());
        }
    }

    @Test
    @DisplayName("無効な画像ファイルの場合はUseCaseExceptionがスローされる")
    void test5() throws Exception {
        MockMultipartFile badImg = new MockMultipartFile(
                "profileImage", "test.png", "image/png", "dummy".getBytes(StandardCharsets.UTF_8));

        UpdateUserInfoCommand req = new UpdateUserInfoCommand(USER_ID, "User", toProfileImage(badImg), false);

        try (MockedStatic<FileUtil> util = mockStatic(FileUtil.class)) {
            util.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(true);
            util.when(() -> FileUtil.isImageReadValid(any())).thenReturn(false);

            assertThatThrownBy(() -> {
                updateUserInfoUseCase.execute(req);
            }).isInstanceOf(UseCaseException.class)
                    .matches(e -> ((UseCaseException) e).getErrors().containsKey("profileImage"));

            verify(objectStore, never()).putAs(any(), any(), any());
            verify(userRepository, never()).save(any());
        }
    }

    @Test
    @DisplayName("S3へのアップロードに失敗した場合、UseCaseExceptionがスローされる")
    void test6() throws IOException {
        UpdateUserInfoCommand req = new UpdateUserInfoCommand(
                USER_ID,
                "Valid",
                toProfileImage(PROFILE_IMAGE),
                true);

        ErrorCollector errorCollector = new ErrorCollector();
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(
                User.reconstruct(
                        USER_ID,
                        Email.create(errorCollector, "a@b.com"),
                        "pw",
                        false,
                        Map.of(),
                        EnumSet.of(RoleName.USER),
                        null,
                        "",
                        LocalDateTime.now(),
                        LocalDateTime.now())));

        try (MockedStatic<FileUtil> util = mockStatic(FileUtil.class)) {
            util.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(true);
            util.when(() -> FileUtil.isImageReadValid(any())).thenReturn(true);
            util.when(() -> FileUtil.getExtension(any())).thenReturn("png");
            when(objectStore.putAs(any(StoredObject.class), eq("/profile/image/"), eq(USER_ID + ".png")))
                    .thenThrow(new UseCaseException("S3 error"));

            assertThatThrownBy(() -> {
                updateUserInfoUseCase.execute(req);
            }).isInstanceOf(UseCaseException.class)
                    .hasMessage("S3 error");

            verify(objectStore, never()).put(any(), any());
        }
    }

    @Test
    @DisplayName("ユーザーが存在しない場合、AuthenticationCredentialsNotFoundExceptionがスローされる")
    void test7() {
        UpdateUserInfoCommand req = new UpdateUserInfoCommand(USER_ID, "Valid", toProfileImage(PROFILE_IMAGE), true);

        when(userRepository.findById(USER_ID)).thenReturn(Optional.empty());
        try (MockedStatic<FileUtil> util = mockStatic(FileUtil.class)) {
            util.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(true);
            util.when(() -> FileUtil.isImageReadValid(any())).thenReturn(true);

            assertThatThrownBy(() -> {
                updateUserInfoUseCase.execute(req);
            }).isInstanceOf(AuthenticationCredentialsNotFoundException.class)
                    .hasMessage("不正なアクセスです。");

            verify(objectStore, never()).putAs(any(), any(), any());
            verify(objectStore, never()).put(any(), any());
        }
    }

    private ProfileImageCommand toProfileImage(MultipartFile file) {
        try {
            return new ProfileImageCommand(file.getBytes(), file.getContentType(), file.getOriginalFilename());
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
    }

}
