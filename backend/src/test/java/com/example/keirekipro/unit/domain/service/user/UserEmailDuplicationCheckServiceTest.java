package com.example.keirekipro.unit.domain.service.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.domain.service.user.UserEmailDuplicationCheckService;
import com.example.keirekipro.shared.Notification;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class UserEmailDuplicationCheckServiceTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private Notification notification;

    @InjectMocks
    private UserEmailDuplicationCheckService service;

    private static final UUID USER_ID_1 = UUID.fromString("111e4567-e89b-12d3-a456-426614174000");
    private static final UUID USER_ID_2 = UUID.fromString("222e4567-e89b-12d3-a456-426614174000");

    private static final String EMAIL = "user@keirekipro.click";
    private static final String PASSWORD_HASH = "passwordHash";
    private static final String PROFILE_IMAGE = "profile/user.png";
    private static final String USERNAME = "test-user";
    private static final LocalDateTime CREATED_AT = LocalDateTime.now();
    private static final LocalDateTime UPDATED_AT = LocalDateTime.now();

    @Test
    @DisplayName("メールアドレスがnullの場合、重複チェック不要")
    void test1() {
        // メールアドレスがnullのユーザーを作成
        User user = User.reconstruct(
                USER_ID_1,
                null,
                PASSWORD_HASH,
                false,
                Collections.emptyMap(),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT);

        // 重複チェックを実行
        boolean result = service.execute(user);

        // 重複チェック不要のため、falseとなる
        assertThat(result).isFalse();
    }

    @Test
    @DisplayName("メールアドレスが存在し、他ユーザーに同じメールアドレスが使われていない場合、重複なし")
    void test2() {
        // テスト対象のユーザーを作成
        Email email = Email.create(notification, EMAIL);
        User user = User.reconstruct(
                USER_ID_1,
                email,
                PASSWORD_HASH,
                false,
                Collections.emptyMap(),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT);

        // モックをセットアップ
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());

        // 重複チェックを実行
        boolean result = service.execute(user);

        // 重複がないため、falseとなる
        assertThat(result).isFalse();
    }

    @Test
    @DisplayName("メールアドレスが存在し、他ユーザーに同じメールアドレスが使われている場合、重複あり")
    void test3() {
        // テスト対象のユーザーを作成
        Email email = Email.create(notification, EMAIL);
        User user = User.reconstruct(
                USER_ID_1,
                email,
                PASSWORD_HASH,
                false,
                Collections.emptyMap(),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT);

        // 同じメールアドレスを持つ別ユーザーを作成（IDが異なる）
        User existingUser = User.reconstruct(
                USER_ID_2,
                email,
                PASSWORD_HASH,
                false,
                Collections.emptyMap(),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT);

        // モックをセットアップ
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(existingUser));

        // 重複チェックを実行
        boolean result = service.execute(user);

        // 重複しているため、trueとなる
        assertThat(result).isTrue();
    }

    @Test
    @DisplayName("メールアドレスが存在し、同一ユーザーの場合は重複とみなさない")
    void test4() {
        // テスト対象のユーザーを作成
        Email email = Email.create(notification, EMAIL);
        User user = User.reconstruct(
                USER_ID_1,
                email,
                PASSWORD_HASH,
                false,
                Collections.emptyMap(),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT);

        // リポジトリから返却されるのは同じユーザー（IDが一致）
        User existingUser = User.reconstruct(
                USER_ID_1,
                email,
                PASSWORD_HASH,
                false,
                Collections.emptyMap(),
                PROFILE_IMAGE,
                USERNAME,
                CREATED_AT,
                UPDATED_AT);

        // モックをセットアップ
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(existingUser));

        // 重複チェックを実行
        boolean result = service.execute(user);

        // 同一ユーザーは重複とみなさないため、falseとなる
        assertThat(result).isFalse();
    }
}
