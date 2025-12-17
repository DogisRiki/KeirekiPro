package com.example.keirekipro.unit.presentation.resume.controller;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.UUID;

import com.example.keirekipro.presentation.resume.controller.DeleteSocialLinkController;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.DeleteSocialLinkUseCase;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.TestConstructor.AutowireMode;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(DeleteSocialLinkController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = AutowireMode.ALL)
@RequiredArgsConstructor
class DeleteSocialLinkControllerTest {

    @MockitoBean
    private DeleteSocialLinkUseCase deleteSocialLinkUseCase;

    @MockitoBean
    private CurrentUserFacade currentUserFacade;

    private final MockMvc mockMvc;

    private static final String ENDPOINT = "/api/resumes/{resumeId}/social-links/{socialLinkId}";
    private static final UUID USER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID RESUME_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID SOCIAL_LINK_ID = UUID.fromString("33333333-3333-3333-3333-333333333333");

    @Test
    @DisplayName("正常なリクエストの場合、204が返り、ユースケースが呼び出される")
    void test1() throws Exception {
        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());

        mockMvc.perform(delete(ENDPOINT, RESUME_ID, SOCIAL_LINK_ID))
                .andExpect(status().isNoContent());

        verify(currentUserFacade).getUserId();
        verify(deleteSocialLinkUseCase).execute(eq(USER_ID), eq(RESUME_ID), eq(SOCIAL_LINK_ID));
    }
}
