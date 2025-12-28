package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.usecase.auth.TwoFactorAuthVerifyUseCase;
import com.example.keirekipro.usecase.auth.store.TwoFactorAuthCodeStore;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class TwoFactorAuthVerifyUseCaseTest {

    @Mock
    private TwoFactorAuthCodeStore twoFactorAuthCodeStore;

    @InjectMocks
    private TwoFactorAuthVerifyUseCase twoFactorAuthVerifyUseCase;

    private static final UUID USER_ID = UUID.randomUUID();
    private static final String CODE = "012345";

    @Test
    @DisplayName("2段階認証コードの検証がOK")
    void test1() {
        // モックをセットアップ
        when(twoFactorAuthCodeStore.find(USER_ID)).thenReturn(Optional.of(CODE));

        // ユースケース実行
        assertThatCode(() -> {
            twoFactorAuthVerifyUseCase.execute(USER_ID, CODE);
        }).doesNotThrowAnyException();

        // 検証
        verify(twoFactorAuthCodeStore).remove(USER_ID);
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
    }
}
