package com.example.keirekipro.unit.presentation.snsplatform.controller;

import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;

import com.example.keirekipro.presentation.snsplatform.controller.GetSnsPlatformListController;
import com.example.keirekipro.usecase.snsplatform.GetSnsPlatformListUseCase;
import com.example.keirekipro.usecase.snsplatform.dto.SnsPlatformListUseCaseDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.TestConstructor.AutowireMode;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(GetSnsPlatformListController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = AutowireMode.ALL)
@RequiredArgsConstructor
class GetSnsPlatformListControllerTest {

    @MockitoBean
    private GetSnsPlatformListUseCase getSnsPlatformListUseCase;

    private final MockMvc mockMvc;

    private static final String ENDPOINT = "/api/sns-platforms";

    @Test
    @DisplayName("正常なリクエストの場合、200とSNSプラットフォーム一覧がレスポンスとして返る")
    void test1() throws Exception {
        // UseCaseから返却されるDTOを準備
        SnsPlatformListUseCaseDto dto = SnsPlatformListUseCaseDto.create(
                List.of("X", "Instagram", "YouTube"));

        // モック設定
        when(getSnsPlatformListUseCase.execute()).thenReturn(dto);

        // 実行&検証
        mockMvc.perform(get(ENDPOINT))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.names[0]").value("X"))
                .andExpect(jsonPath("$.names[1]").value("Instagram"))
                .andExpect(jsonPath("$.names[2]").value("YouTube"));

        verify(getSnsPlatformListUseCase).execute();
    }

    @Test
    @DisplayName("SNSプラットフォームが1件も存在しない場合、200と空リストがレスポンスとして返る")
    void test2() throws Exception {
        // 空リストのDTOを準備
        SnsPlatformListUseCaseDto dto = SnsPlatformListUseCaseDto.create(List.of());

        // モック設定
        when(getSnsPlatformListUseCase.execute()).thenReturn(dto);

        // 実行&検証
        mockMvc.perform(get(ENDPOINT))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.names").isEmpty());

        verify(getSnsPlatformListUseCase).execute();
    }
}
