package com.example.keirekipro.unit.presentation.user.controller;

import static org.hamcrest.Matchers.hasItem;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;
import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.presentation.user.controller.SetEmailAndPasswordController;
import com.example.keirekipro.presentation.user.dto.SetEmailAndPasswordRequest;
import com.example.keirekipro.usecase.user.GetUserInfoUseCase;
import com.example.keirekipro.usecase.user.SetEmailAndPasswordUseCase;
import com.example.keirekipro.usecase.user.dto.UserInfoUseCaseDto;
import com.example.keirekipro.usecase.user.dto.UserInfoUseCaseDto.AuthProviderInfo;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(SetEmailAndPasswordController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class SetEmailAndPasswordControllerTest {

    @MockitoBean
    private final SetEmailAndPasswordUseCase setEmailAndPasswordUseCase;

    @MockitoBean
    private final GetUserInfoUseCase getUserInfoUseCase;

    @MockitoBean
    private final CurrentUserFacade currentUserFacade;

    private final MockMvc mockMvc;

    private final ObjectMapper objectMapper = new ObjectMapper();

    private static final String ENDPOINT = "/api/users/me/email-password";

    private static final String USER_ID = "123e4567-e89b-12d3-a456-426614174000";
    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME = "test-user";
    private static final String PROFILE_IMAGE_URL = "https://signed-url.example.com/dog.jpg";
    private static final String PASSWORD = "Password123";
    private static final UUID AUTH_PROVIDER_ID = UUID.fromString("f47ac10b-58cc-4372-a567-0e02b2c3d479");
    private static final String PROVIDER_NAME = "google";
    private static final String PROVIDER_USER_ID = "109876543210987654321";

    @Test
    @DisplayName("正常にメールアドレスとパスワードを設定できる")
    void test1() throws Exception {
        SetEmailAndPasswordRequest request = new SetEmailAndPasswordRequest(
                EMAIL,
                PASSWORD,
                PASSWORD);
        String json = objectMapper.writeValueAsString(request);

        UserInfoUseCaseDto.AuthProviderInfo authProvider = new AuthProviderInfo(
                AUTH_PROVIDER_ID, PROVIDER_NAME, PROVIDER_USER_ID);

        UserInfoUseCaseDto dto = UserInfoUseCaseDto.builder()
                .id(UUID.fromString(USER_ID))
                .email(EMAIL)
                .username(USERNAME)
                .hasPassword(true)
                .profileImage(PROFILE_IMAGE_URL)
                .twoFactorAuthEnabled(true)
                .authProviders(List.of(authProvider))
                .build();

        when(currentUserFacade.getUserId()).thenReturn(USER_ID);
        when(getUserInfoUseCase.execute(UUID.fromString(USER_ID))).thenReturn(dto);

        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(json))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(USER_ID))
                .andExpect(jsonPath("$.email").value(EMAIL))
                .andExpect(jsonPath("$.username").value(USERNAME))
                .andExpect(jsonPath("$.hasPassword").value(true))
                .andExpect(jsonPath("$.profileImage").value(PROFILE_IMAGE_URL))
                .andExpect(jsonPath("$.twoFactorAuthEnabled").value(true))
                .andExpect(jsonPath("$.authProviders[0]").value(PROVIDER_NAME));

        verify(setEmailAndPasswordUseCase).execute(UUID.fromString(USER_ID), request);
    }

    @Test
    @DisplayName("メールアドレス形式が不正な場合、バリデーションエラーとなる")
    void test2() throws Exception {
        SetEmailAndPasswordRequest request = new SetEmailAndPasswordRequest("invalid-email", PASSWORD, PASSWORD);

        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.email").exists())
                .andExpect(jsonPath("$.errors.email", hasItem("メールアドレスの形式が無効です。")));
    }

    @Test
    @DisplayName("メールアドレスが255文字を超える場合、バリデーションエラーとなる")
    void test3() throws Exception {
        String longEmail = "a".repeat(245) + "@example.com";
        SetEmailAndPasswordRequest request = new SetEmailAndPasswordRequest(longEmail, PASSWORD, PASSWORD);

        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.email").exists())
                .andExpect(jsonPath("$.errors.email", hasItem("メールアドレスは255文字以内で入力してください。")));
    }

    @Test
    @DisplayName("パスワードが空の場合、バリデーションエラーとなる")
    void test4() throws Exception {
        SetEmailAndPasswordRequest request = new SetEmailAndPasswordRequest("test@example.com", "", "");

        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.password").exists())
                .andExpect(jsonPath("$.errors.password", hasItem("パスワードは入力必須です。")));
    }

    @Test
    @DisplayName("メールアドレスがnullでも設定可能")
    void test5() throws Exception {
        SetEmailAndPasswordRequest request = new SetEmailAndPasswordRequest(
                null,
                PASSWORD,
                PASSWORD);
        String json = objectMapper.writeValueAsString(request);

        UserInfoUseCaseDto dto = UserInfoUseCaseDto.builder()
                .id(UUID.fromString(USER_ID))
                .email(null)
                .username(USERNAME)
                .hasPassword(true)
                .profileImage(null)
                .twoFactorAuthEnabled(false)
                .authProviders(List.of())
                .build();

        when(currentUserFacade.getUserId()).thenReturn(USER_ID);
        when(getUserInfoUseCase.execute(UUID.fromString(USER_ID))).thenReturn(dto);

        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(json))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(USER_ID))
                .andExpect(jsonPath("$.email").doesNotExist())
                .andExpect(jsonPath("$.username").value(USERNAME))
                .andExpect(jsonPath("$.hasPassword").value(true))
                .andExpect(jsonPath("$.profileImage").doesNotExist())
                .andExpect(jsonPath("$.twoFactorAuthEnabled").value(false))
                .andExpect(jsonPath("$.authProviders").isArray());

        verify(setEmailAndPasswordUseCase).execute(UUID.fromString(USER_ID), request);
    }

    @Test
    @DisplayName("パスワードがnullの場合、バリデーションエラーとなる")
    void test6() throws Exception {
        SetEmailAndPasswordRequest request = new SetEmailAndPasswordRequest(
                EMAIL,
                null,
                null);

        String json = objectMapper.writeValueAsString(request);

        mockMvc.perform(post(
                ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(json))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("メールアドレスとパスワードの両方がnullの場合、バリデーションエラーとなる")
    void test7() throws Exception {
        SetEmailAndPasswordRequest request = new SetEmailAndPasswordRequest(
                null,
                null,
                null);

        String json = objectMapper.writeValueAsString(request);

        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(json))
                .andExpect(status().isBadRequest());
    }
}
