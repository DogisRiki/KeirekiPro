package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.EnumSet;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.RoleName;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.auth.TwoFactorAuthVerifyUseCase;
import com.example.keirekipro.usecase.auth.dto.TwoFactorAuthVerifyResultDto;
import com.example.keirekipro.usecase.auth.store.TwoFactorAuthCodeStore;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InOrder;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class TwoFactorAuthVerifyUseCaseTest {

    @Mock
    private TwoFactorAuthCodeStore twoFactorAuthCodeStore;

    @Mock
    private UserRepository userRepository;

    @InjectMocks
    private TwoFactorAuthVerifyUseCase twoFactorAuthVerifyUseCase;

    private static final UUID USER_ID = UUID.randomUUID();
    private static final String CODE = "012345";

    @Test
    @DisplayName("2段階認証コードの検証がOK")
    void test1() {
        // モックをセットアップ
        when(twoFactorAuthCodeStore.find(USER_ID)).thenReturn(Optional.of(CODE));

        ErrorCollector errorCollector = new ErrorCollector();
        User user = User.reconstruct(
                USER_ID,
                Email.create(errorCollector, "test@keirekipro.click"),
                null,
                false,
                Collections.emptyMap(),
                EnumSet.of(RoleName.USER),
                null,
                "test-user",
                LocalDateTime.now(),
                LocalDateTime.now());
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));

        // ユースケース実行
        TwoFactorAuthVerifyResultDto result = twoFactorAuthVerifyUseCase.execute(USER_ID, CODE);

        // 検証
        assertThat(result).isNotNull();
        assertThat(result.getUserId()).isEqualTo(USER_ID);
        assertThat(result.getRoles()).containsExactlyInAnyOrder("USER");

        InOrder inOrder = inOrder(twoFactorAuthCodeStore, userRepository);
        inOrder.verify(twoFactorAuthCodeStore).remove(USER_ID);
        inOrder.verify(userRepository).findById(USER_ID);
    }

    @Test
    @DisplayName("2段階認証コードが期限切れの場合、UseCaseExceptionがスローされる")
    void test2() {
        // モックをセットアップ
        when(twoFactorAuthCodeStore.find(USER_ID)).thenReturn(Optional.empty());

        // ユースケース実行
        assertThatThrownBy(() -> {
            twoFactorAuthVerifyUseCase.execute(USER_ID, CODE);
        })
                .isInstanceOf(UseCaseException.class)
                .hasMessage("認証コードが無効または期限切れです。もう一度最初からお試しください。");

        // 検証
        verify(twoFactorAuthCodeStore, never()).remove(any());
        verify(userRepository, never()).findById(any());
    }

    @Test
    @DisplayName("2段階認証コードの検証がNGの場合、UseCaseExceptionがスローされる")
    void test3() {
        // モックをセットアップ
        when(twoFactorAuthCodeStore.find(USER_ID)).thenReturn(Optional.of(CODE));

        // ユースケース実行
        assertThatThrownBy(() -> {
            twoFactorAuthVerifyUseCase.execute(USER_ID, "999999");
        })
                .isInstanceOf(UseCaseException.class)
                .hasMessage("認証コードが無効または期限切れです。もう一度最初からお試しください。");

        // 検証
        verify(twoFactorAuthCodeStore, never()).remove(any());
        verify(userRepository, never()).findById(any());
    }

    @Test
    @DisplayName("認証コードが正しくてもユーザーが存在しない場合、UseCaseExceptionがスローされる")
    void test4() {
        // モックをセットアップ
        when(twoFactorAuthCodeStore.find(USER_ID)).thenReturn(Optional.of(CODE));
        when(userRepository.findById(USER_ID)).thenReturn(Optional.empty());

        // ユースケース実行
        assertThatThrownBy(() -> {
            twoFactorAuthVerifyUseCase.execute(USER_ID, CODE);
        })
                .isInstanceOf(UseCaseException.class)
                .hasMessage("ユーザー情報の取得に失敗しました。");

        // 検証（コード検証OKの場合は削除が先に走る）
        InOrder inOrder = inOrder(twoFactorAuthCodeStore, userRepository);
        inOrder.verify(twoFactorAuthCodeStore).remove(USER_ID);
        inOrder.verify(userRepository).findById(USER_ID);
    }
}
