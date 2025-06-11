package com.example.keirekipro.unit.domain.service.user;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Collections;
import java.util.Optional;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.domain.service.user.UserEmailDuplicationCheckService;
import com.example.keirekipro.domain.shared.exception.DomainException;
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

    private static final String EMAIL = "user@keirekipro.click";

    @Test
    @DisplayName("メールアドレスがnullの場合、重複チェックが行われない")
    void test1() {
        // メールアドレスがnullのユーザーを作成
        Email email = null;

        // 重複チェックを実行
        assertThatCode(() -> service.execute(email)).doesNotThrowAnyException();

        // ユーザー検索が呼ばれない
        verify(userRepository, never()).findByEmail(any());
    }

    @Test
    @DisplayName("同一のメールアドレスが存在する場合、DomainExceptionをスローする")
    void test2() {
        // テスト対象のユーザーを作成
        Email email = Email.create(notification, EMAIL);
        User user = User.reconstruct(
                null,
                email,
                null,
                false,
                Collections.emptyMap(),
                null,
                null,
                null,
                null);

        // モックをセットアップ
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(user));

        // 重複チェックを実行
        assertThatThrownBy(
                () -> service.execute(Email.create(notification, EMAIL))).isInstanceOf(DomainException.class)
                .hasMessage("このメールアドレスは登録できません。");
    }

    @Test
    @DisplayName("同一のメールアドレスが存在しない場合、DomainExceptionがスローされない")
    void test3() {
        Email email = Email.create(notification, EMAIL);

        // モックをセットアップ
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());

        // 重複チェックを実行
        assertThatCode(() -> service.execute(email)).doesNotThrowAnyException();

        // ユーザー検索が呼ばれる
        verify(userRepository, times(1)).findByEmail(email.getValue());
    }
}
