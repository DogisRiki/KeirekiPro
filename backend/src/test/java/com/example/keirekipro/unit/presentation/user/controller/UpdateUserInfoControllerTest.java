package com.example.keirekipro.unit.presentation.user.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;
import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.presentation.user.controller.UpdateUserInfoController;
import com.example.keirekipro.usecase.user.UpdateUserInfoUseCase;
import com.example.keirekipro.usecase.user.dto.UserInfoUseCaseDto;
import com.example.keirekipro.usecase.user.dto.UserInfoUseCaseDto.AuthProviderInfo;

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

    private static final String ENDPOINT = "/api/users/me";
    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME = "test-user";
    private static final String PROFILE_IMAGE_URL = "https://signed-url.example.com/dog.jpg";
    private static final boolean TWO_FACTOR_AUTH_ENABLED = false;
    private static final UUID AUTH_PROVIDER_ID = UUID.fromString("f47ac10b-58cc-4372-a567-0e02b2c3d479");
    private static final String PROVIDER_NAME = "google";
    private static final String PROVIDER_USER_ID = "109876543210987654321";

    private static final MockMultipartFile PROFILE_IMAGE = new MockMultipartFile(
            "profileImage",
            "test.png",
            "image/png",
            new byte[] {
                    (byte) 0x89, 0x50, 0x4E, 0x47,
                    0x0D, 0x0A, 0x1A, 0x0A
            });

    @Test
    @DisplayName("正常なリクエストの場合、200が返される")
    void test1() throws Exception {
        // ダミーのユースケースDTOを生成
        AuthProviderInfo authProvider = new AuthProviderInfo(AUTH_PROVIDER_ID, PROVIDER_NAME, PROVIDER_USER_ID);
        UserInfoUseCaseDto dto = UserInfoUseCaseDto.builder()
                .id(USER_ID)
                .email(EMAIL)
                .username(USERNAME)
                .hasPassword(false)
                .profileImage(PROFILE_IMAGE_URL)
                .twoFactorAuthEnabled(TWO_FACTOR_AUTH_ENABLED)
                .authProviders(List.of(authProvider))
                .build();

        // モックをセットアップ
        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        when(updateUserInfoUseCase.execute(any(), eq(USER_ID))).thenReturn(dto);

        // リクエストを実行
        mockMvc.perform(
                multipart(ENDPOINT)
                        .file(PROFILE_IMAGE)
                        .param("username", USERNAME)
                        .param("twoFactorAuthEnabled", "true")
                        .with(req -> {
                            req.setMethod("PUT");
                            return req;
                        }))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(USER_ID.toString()))
                .andExpect(jsonPath("$.email").value(EMAIL))
                .andExpect(jsonPath("$.username").value(USERNAME))
                .andExpect(jsonPath("$.hasPassword").value(false))
                .andExpect(jsonPath("$.profileImage").value(PROFILE_IMAGE_URL))
                .andExpect(jsonPath("$.twoFactorAuthEnabled").value(TWO_FACTOR_AUTH_ENABLED))
                .andExpect(jsonPath("$.authProviders[0]").value(PROVIDER_NAME));

        // 呼び出しを検証
        verify(currentUserFacade).getUserId();
        verify(updateUserInfoUseCase).execute(any(), eq(USER_ID));
    }
}
