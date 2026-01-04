package com.example.keirekipro.unit.usecase.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.io.IOException;
import java.time.LocalDateTime;
import java.util.EnumSet;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.AuthProvider;
import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.RoleName;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.presentation.user.dto.UpdateUserInfoRequest;
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
    private static final byte[] PROFILE_IMAGE_BYTES = new byte[] {
            (byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
    };
    private static final MockMultipartFile PROFILE_IMAGE = new MockMultipartFile("profileImage", "test.png",
            "image/png", PROFILE_IMAGE_BYTES);

    // uploadFile の戻り値（S3キー）
    private static final String S3_KEY = "s3-key";

    @Test
    @DisplayName("正常にユーザー情報更新ができる")
    void test1() throws IOException {
        // リクエスト準備
        UpdateUserInfoRequest request = new UpdateUserInfoRequest();
        request.setUsername(USERNAME);
        request.setProfileImage(PROFILE_IMAGE);
        request.setTwoFactorAuthEnabled(true);

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
            updateUserInfoUseCase.execute(request, USER_ID);

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

        UpdateUserInfoRequest req = new UpdateUserInfoRequest();
        req.setUsername("User");
        req.setProfileImage(badFile);
        req.setTwoFactorAuthEnabled(false);

        try (MockedStatic<FileUtil> util = mockStatic(FileUtil.class)) {
            util.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(false);
            util.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(true);
            util.when(() -> FileUtil.isImageReadValid(any())).thenReturn(true);

            assertThatThrownBy(() -> {
                updateUserInfoUseCase.execute(req, USER_ID);
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

        UpdateUserInfoRequest req = new UpdateUserInfoRequest();
        req.setUsername("User");
        req.setProfileImage(badExt);
        req.setTwoFactorAuthEnabled(false);

        try (MockedStatic<FileUtil> util = mockStatic(FileUtil.class)) {
            util.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(false);
            util.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(true);
            util.when(() -> FileUtil.isImageReadValid(any())).thenReturn(true);

            assertThatThrownBy(() -> {
                updateUserInfoUseCase.execute(req, USER_ID);
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

        UpdateUserInfoRequest req = new UpdateUserInfoRequest();
        req.setUsername("User");
        req.setProfileImage(bigFile);
        req.setTwoFactorAuthEnabled(false);

        try (MockedStatic<FileUtil> util = mockStatic(FileUtil.class)) {
            util.when(() -> FileUtil.isMimeTypeValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isExtensionValid(any(), anyList())).thenReturn(true);
            util.when(() -> FileUtil.isFileSizeValid(any(), anyLong())).thenReturn(false);
            util.when(() -> FileUtil.isImageReadValid(any())).thenReturn(true);

            assertThatThrownBy(() -> {
                updateUserInfoUseCase.execute(req, USER_ID);
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

            assertThatThrownBy(() -> {
                updateUserInfoUseCase.execute(req, USER_ID);
            }).isInstanceOf(UseCaseException.class)
                    .matches(e -> ((UseCaseException) e).getErrors().containsKey("profileImage"));

            verify(objectStore, never()).putAs(any(), any(), any());
            verify(userRepository, never()).save(any());
        }
    }

    @Test
    @DisplayName("S3へのアップロードに失敗した場合、UseCaseExceptionがスローされる")
    void test6() throws IOException {
        UpdateUserInfoRequest req = new UpdateUserInfoRequest();
        req.setUsername("Valid");

        // MultipartFile.getBytes()がIOExceptionを投げるケースを作る
        MultipartFile profileImageMock = mock(MultipartFile.class);
        when(profileImageMock.isEmpty()).thenReturn(false);
        when(profileImageMock.getBytes()).thenThrow(new IOException("S3 error"));
        req.setProfileImage(profileImageMock);

        req.setTwoFactorAuthEnabled(true);

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

            assertThatThrownBy(() -> {
                updateUserInfoUseCase.execute(req, USER_ID);
            }).isInstanceOf(UseCaseException.class)
                    .hasMessage("プロフィール画像のアップロードに失敗しました。しばらく時間を置いてから再度お試しください。");

            verify(objectStore, never()).putAs(any(), any(), any());
            verify(objectStore, never()).put(any(), any());
        }
    }

    @Test
    @DisplayName("ユーザーが存在しない場合、AuthenticationCredentialsNotFoundExceptionがスローされる")
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

            assertThatThrownBy(() -> {
                updateUserInfoUseCase.execute(req, USER_ID);
            }).isInstanceOf(AuthenticationCredentialsNotFoundException.class)
                    .hasMessage("不正なアクセスです。");

            verify(objectStore, never()).putAs(any(), any(), any());
            verify(objectStore, never()).put(any(), any());
        }
    }
}
