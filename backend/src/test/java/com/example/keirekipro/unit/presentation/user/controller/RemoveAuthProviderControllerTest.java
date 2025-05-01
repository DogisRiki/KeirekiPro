package com.example.keirekipro.unit.presentation.user.controller;

import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.presentation.user.controller.RemoveAuthProviderController;
import com.example.keirekipro.usecase.user.RemoveAuthProviderUseCase;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(RemoveAuthProviderController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class RemoveAuthProviderControllerTest {

    @MockitoBean
    private final RemoveAuthProviderUseCase removeAuthProviderUseCase;

    @MockitoBean
    private final CurrentUserFacade currentUserFacade;

    private final MockMvc mockMvc;

    private static final UUID USER_ID = UUID.randomUUID();
    private static final String PROVIDER = "github";

    @Test
    @DisplayName("外部認証連携解除が正常に完了する")
    void test1() throws Exception {
        // モックセットアップ
        String userId = USER_ID.toString();
        when(currentUserFacade.getUserId()).thenReturn(userId);

        // リクエストを実行
        mockMvc.perform(delete("/api/users/me/auth-provider/{provider}", PROVIDER)
                .contentType("application/json"))
                .andExpect(status().isNoContent());

        // 呼び出しを検証
        verify(currentUserFacade).getUserId();
        verify(removeAuthProviderUseCase).execute(USER_ID, PROVIDER);
    }
}
