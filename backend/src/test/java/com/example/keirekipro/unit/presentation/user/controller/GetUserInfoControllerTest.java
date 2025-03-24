package com.example.keirekipro.unit.presentation.user.controller;

import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;
import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.presentation.user.controller.GetUserInfoController;
import com.example.keirekipro.usecase.user.GetUserInfoUseCase;
import com.example.keirekipro.usecase.user.dto.GetUserInfoUseCaseDto;
import com.example.keirekipro.usecase.user.dto.GetUserInfoUseCaseDto.AuthProviderInfo;

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

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME = "test-user";
    private static final byte[] PROFILE_IMAGE_DATA = new byte[] { 0x12, 0x34, 0x56 };
    private static final boolean TWO_FACTOR_AUTH_ENABLED = false;
    private static final UUID AUTH_PROVIDER_ID = UUID.fromString("f47ac10b-58cc-4372-a567-0e02b2c3d479");
    private static final String PROVIDER_TYPE = "GOOGLE";
    private static final String PROVIDER_USER_ID = "109876543210987654321";

    @Test
    @DisplayName("正常なリクエストの場合、200が返される")
    void test1() throws Exception {
        // ダミーのユースケースDTOを生成
        AuthProviderInfo authProvider = new AuthProviderInfo(AUTH_PROVIDER_ID, PROVIDER_TYPE, PROVIDER_USER_ID);
        GetUserInfoUseCaseDto dto = GetUserInfoUseCaseDto.builder()
                .id(USER_ID)
                .email(EMAIL)
                .username(USERNAME)
                .profileImage(PROFILE_IMAGE_DATA)
                .twoFactorAuthEnabled(TWO_FACTOR_AUTH_ENABLED)
                .authProviders(List.of(authProvider))
                .build();

        // モックをセットアップ
        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        when(getUserInfoUseCase.execute(USER_ID)).thenReturn(dto);

        // GETリクエストを実行し、レスポンスの内容を検証
        mockMvc.perform(get("/api/users/me"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(USER_ID.toString()))
                .andExpect(jsonPath("$.email").value(EMAIL))
                .andExpect(jsonPath("$.username").value(USERNAME))
                .andExpect(jsonPath("$.profileImage").value("EjRW")) // JSON上はBase64エンコードされるので、"EjRW"になる
                .andExpect(jsonPath("$.twoFactorAuthEnabled").value(TWO_FACTOR_AUTH_ENABLED))
                .andExpect(jsonPath("$.authProviders[0].id").value(AUTH_PROVIDER_ID.toString()))
                .andExpect(jsonPath("$.authProviders[0].providerType").value(PROVIDER_TYPE))
                .andExpect(jsonPath("$.authProviders[0].providerUserId").value(PROVIDER_USER_ID));
    }
}
