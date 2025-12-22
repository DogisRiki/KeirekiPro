package com.example.keirekipro.unit.presentation.resume.controller;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.UUID;

import com.example.keirekipro.presentation.resume.controller.DeleteSelfPromotionController;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.DeleteSelfPromotionUseCase;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.TestConstructor.AutowireMode;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(DeleteSelfPromotionController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = AutowireMode.ALL)
@RequiredArgsConstructor
class DeleteSelfPromotionControllerTest {

    @MockitoBean
    private DeleteSelfPromotionUseCase useCase;

    @MockitoBean
    private CurrentUserFacade currentUserFacade;

    private final MockMvc mockMvc;

    private static final String ENDPOINT = "/api/resumes/{resumeId}/self-promotions/{selfPromotionId}";
    private static final UUID USER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID RESUME_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID SELF_PROMOTION_ID = UUID.fromString("33333333-3333-3333-3333-333333333333");

    @Test
    @DisplayName("正常なリクエストの場合、204が返り、ユースケースが呼び出される")
    void test1() throws Exception {
        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());

        mockMvc.perform(delete(ENDPOINT, RESUME_ID, SELF_PROMOTION_ID))
                .andExpect(status().isNoContent());

        verify(currentUserFacade).getUserId();
        verify(useCase).execute(eq(USER_ID), eq(RESUME_ID), eq(SELF_PROMOTION_ID));
    }
}
