package com.example.keirekipro.unit.presentation.user.controller;

import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.presentation.user.controller.DeleteUserController;
import com.example.keirekipro.usecase.user.DeleteUserUseCase;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(DeleteUserController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class DeleteUserControllerTest {

    @MockitoBean
    private DeleteUserUseCase deleteUserUseCase;

    @MockitoBean
    private CurrentUserFacade currentUserFacade;

    private final MockMvc mockMvc;

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");

    @Test
    @DisplayName("正常なリクエストの場合、204が返される")
    void test1() throws Exception {
        // モックをセットアップ
        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());

        // リクエストを実行
        mockMvc.perform(delete("/api/users/me")
                .contentType(MediaType.APPLICATION_JSON))
                .andExpect(status().isNoContent());

        // 呼び出しを検証
        verify(currentUserFacade).getUserId();
        verify(deleteUserUseCase).execute(USER_ID);
    }
}
