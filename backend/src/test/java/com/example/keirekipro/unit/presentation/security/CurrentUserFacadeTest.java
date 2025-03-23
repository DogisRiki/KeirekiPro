package com.example.keirekipro.unit.presentation.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

@ExtendWith(MockitoExtension.class)
class CurrentUserFacadeTest {

    @InjectMocks
    private CurrentUserFacade currentUserFacade;

    @AfterEach
    void tearDown() {
        // 各テスト後にSecurityContextをクリアする
        SecurityContextHolder.clearContext();
    }

    @Test
    @DisplayName("認証済みの場合、ユーザーIDを取得できる")
    void test1() {
        // テスト用データ
        String userId = UUID.randomUUID().toString();

        // SecurityContextに認証情報をセット
        Authentication auth = new TestingAuthenticationToken(userId, null);
        SecurityContextHolder.getContext().setAuthentication(auth);

        // 実行
        String result = currentUserFacade.getUserId();

        // 検証
        assertThat(result).isEqualTo(userId);
    }

    @Test
    @DisplayName("認証情報がnullの場合、AccessDeniedExceptionがスローされる")
    void test2() {
        // SecurityContextに認証情報をセットしない（nullのまま）
        SecurityContextHolder.clearContext();

        // 実行と検証
        assertThatThrownBy(() -> {
            currentUserFacade.getUserId();
        }).isInstanceOf(AccessDeniedException.class)
                .hasMessageContaining("認証されていないユーザーからのリクエストです。");
    }
}
