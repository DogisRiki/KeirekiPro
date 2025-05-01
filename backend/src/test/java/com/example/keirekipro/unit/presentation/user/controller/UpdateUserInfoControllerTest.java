package com.example.keirekipro.unit.presentation.user.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.Base64;
import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.presentation.user.controller.UpdateUserInfoController;
import com.example.keirekipro.usecase.user.UpdateUserInfoUseCase;
import com.example.keirekipro.usecase.user.dto.UpdateUserInfoUseCaseDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(UpdateUserInfoController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class UpdateUserInfoControllerTest {

    @MockitoBean
    private UpdateUserInfoUseCase updateUserInfoUseCase;

    @MockitoBean
    private CurrentUserFacade currentUserFacade;

    private final MockMvc mockMvc;

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");

    private static final String USERNAME = "test-user";

    private static final byte[] PROFILE_IMAGE_BYTES = new byte[] {
            (byte) 0x89, 0x50, 0x4E, 0x47,
            0x0D, 0x0A, 0x1A, 0x0A
    };

    private static final MockMultipartFile PROFILE_IMAGE = new MockMultipartFile(
            "profileImage",
            "test.png",
            "image/png",
            PROFILE_IMAGE_BYTES);

    @Test
    @DisplayName("正常なリクエストの場合、200が返される")
    void test1() throws Exception {
        // ダミーのユースケースDTOを生成
        UpdateUserInfoUseCaseDto dto = UpdateUserInfoUseCaseDto.builder()
                .id(USER_ID)
                .username(USERNAME)
                .profileImage(PROFILE_IMAGE_BYTES)
                .twoFactorAuthEnabled(true)
                .build();

        // モックをセットアップ
        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        when(updateUserInfoUseCase.execute(any(), eq(USER_ID))).thenReturn(dto);

        // リクエストを実行
        mockMvc.perform(
                multipart("/api/users/me")
                        .file(PROFILE_IMAGE)
                        .param("username", USERNAME)
                        .param("twoFactorAuthEnabled", "true")
                        .with(request -> {
                            request.setMethod("PUT");
                            return request;
                        }))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(USER_ID.toString()))
                .andExpect(jsonPath("$.username").value(USERNAME))
                .andExpect(jsonPath("$.profileImage")
                        .value(Base64.getEncoder().encodeToString(PROFILE_IMAGE_BYTES)))
                .andExpect(jsonPath("$.twoFactorAuthEnabled").value(true));

        // 呼び出しを検証
        verify(currentUserFacade).getUserId();
        verify(updateUserInfoUseCase).execute(any(), eq(USER_ID));
    }
}
