package com.example.keirekipro.unit.presentation.user.controller;

import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;
import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.presentation.user.controller.GetUserInfoController;
import com.example.keirekipro.usecase.user.GetUserInfoUseCase;
import com.example.keirekipro.usecase.user.dto.UserInfoUseCaseDto;
import com.example.keirekipro.usecase.user.dto.UserInfoUseCaseDto.AuthProviderInfo;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(GetUserInfoController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class GetUserInfoControllerTest {

    @MockitoBean
    private GetUserInfoUseCase getUserInfoUseCase;

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

    @Test
    @DisplayName("正常なリクエストの場合、200が返される")
    void test1() throws Exception {
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

        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        when(getUserInfoUseCase.execute(USER_ID)).thenReturn(dto);

        mockMvc.perform(get(ENDPOINT))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(USER_ID.toString()))
                .andExpect(jsonPath("$.email").value(EMAIL))
                .andExpect(jsonPath("$.username").value(USERNAME))
                .andExpect(jsonPath("$.hasPassword").value(false))
                .andExpect(jsonPath("$.profileImage").value(PROFILE_IMAGE_URL))
                .andExpect(jsonPath("$.twoFactorAuthEnabled").value(TWO_FACTOR_AUTH_ENABLED))
                .andExpect(jsonPath("$.authProviders[0]").value(PROVIDER_NAME));

        verify(currentUserFacade).getUserId();
        verify(getUserInfoUseCase).execute(USER_ID);
    }
}
