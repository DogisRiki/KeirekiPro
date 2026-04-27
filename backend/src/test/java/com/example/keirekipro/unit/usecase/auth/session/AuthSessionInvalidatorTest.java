package com.example.keirekipro.unit.usecase.auth.session;

import static org.mockito.Mockito.verify;

import java.util.UUID;

import com.example.keirekipro.usecase.auth.session.AuthSessionInvalidator;
import com.example.keirekipro.usecase.auth.store.RefreshTokenStore;
import com.example.keirekipro.usecase.auth.store.UserTokenVersionStore;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class AuthSessionInvalidatorTest {

    @Mock
    private UserTokenVersionStore userTokenVersionStore;

    @Mock
    private RefreshTokenStore refreshTokenStore;

    @InjectMocks
    private AuthSessionInvalidator authSessionInvalidator;

    private static final UUID USER_ID = UUID.randomUUID();

    @Test
    @DisplayName("invalidateでトークンバージョンの加算とリフレッシュトークンの全削除が行われる")
    void test1() {
        authSessionInvalidator.invalidate(USER_ID);

        verify(userTokenVersionStore).increment(USER_ID);
        verify(refreshTokenStore).removeAllByUser(USER_ID);
    }
}
