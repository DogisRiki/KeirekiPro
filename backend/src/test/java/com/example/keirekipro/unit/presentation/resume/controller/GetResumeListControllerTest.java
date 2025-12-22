package com.example.keirekipro.unit.presentation.resume.controller;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.presentation.resume.controller.GetResumeListController;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.GetResumeListUseCase;
import com.example.keirekipro.usecase.resume.dto.ResumeListUseCaseDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.TestConstructor.AutowireMode;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(GetResumeListController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = AutowireMode.ALL)
@RequiredArgsConstructor
class GetResumeListControllerTest {

    @MockitoBean
    private CurrentUserFacade currentUserFacade;

    @MockitoBean
    private GetResumeListUseCase useCase;

    private final MockMvc mockMvc;

    private static final String ENDPOINT = "/api/resumes";
    private static final UUID USER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID RESUME_ID1 = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID RESUME_ID2 = UUID.fromString("33333333-3333-3333-3333-333333333333");
    private static final String NAME1 = "職務経歴書1";
    private static final String NAME2 = "職務経歴書2";
    private static final LocalDateTime CREATED_AT = LocalDateTime.of(2021, 5, 15, 10, 0);
    private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2021, 5, 18, 15, 30);
    private static final DateTimeFormatter FMT = DateTimeFormatter.ISO_LOCAL_DATE_TIME;

    @Test
    @DisplayName("正常なリクエストの場合、200と職務経歴書一覧がレスポンスとして返る")
    void test1() throws Exception {
        // モック設定
        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());

        // レスポンス
        ResumeListUseCaseDto dto1 = ResumeListUseCaseDto.builder()
                .id(RESUME_ID1)
                .resumeName(NAME1)
                .createdAt(CREATED_AT)
                .updatedAt(UPDATED_AT)
                .build();
        ResumeListUseCaseDto dto2 = ResumeListUseCaseDto.builder()
                .id(RESUME_ID2)
                .resumeName(NAME2)
                .createdAt(CREATED_AT)
                .updatedAt(UPDATED_AT)
                .build();

        when(useCase.execute(eq(USER_ID)))
                .thenReturn(List.of(dto1, dto2));

        // 実行&検証
        mockMvc.perform(get(ENDPOINT))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.resumes[0].id").value(RESUME_ID1.toString()))
                .andExpect(jsonPath("$.resumes[0].resumeName").value(NAME1))
                .andExpect(jsonPath("$.resumes[0].createdAt").value(CREATED_AT.format(FMT)))
                .andExpect(jsonPath("$.resumes[0].updatedAt").value(UPDATED_AT.format(FMT)))
                .andExpect(jsonPath("$.resumes[1].id").value(RESUME_ID2.toString()))
                .andExpect(jsonPath("$.resumes[1].resumeName").value(NAME2))
                .andExpect(jsonPath("$.resumes[1].createdAt").value(CREATED_AT.format(FMT)))
                .andExpect(jsonPath("$.resumes[1].updatedAt").value(UPDATED_AT.format(FMT)));

        verify(currentUserFacade).getUserId();
        verify(useCase).execute(eq(USER_ID));
    }

    @Test
    @DisplayName("職務経歴書が1つも存在しない場合、200と空配列がレスポンスとして返る")
    void test2() throws Exception {
        // モック設定
        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        when(useCase.execute(eq(USER_ID))).thenReturn(List.of());

        // 実行&検証
        mockMvc.perform(get(ENDPOINT))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.resumes").isEmpty());

        verify(currentUserFacade).getUserId();
        verify(useCase).execute(eq(USER_ID));
    }
}
