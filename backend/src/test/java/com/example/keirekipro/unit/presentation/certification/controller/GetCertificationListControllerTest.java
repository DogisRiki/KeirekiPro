package com.example.keirekipro.unit.presentation.certification.controller;

import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;

import com.example.keirekipro.presentation.certification.controller.GetCertificationListController;
import com.example.keirekipro.usecase.query.certification.CertificationListQuery;
import com.example.keirekipro.usecase.query.certification.dto.CertificationListQueryDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.TestConstructor.AutowireMode;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(GetCertificationListController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = AutowireMode.ALL)
@RequiredArgsConstructor
class GetCertificationListControllerTest {

    @MockitoBean
    private CertificationListQuery certificationListQuery;

    private final MockMvc mockMvc;

    private static final String ENDPOINT = "/api/certifications";

    @Test
    @DisplayName("正常なリクエストの場合、200と資格一覧がレスポンスとして返る")
    void test1() throws Exception {
        // Queryから返却されるDTOを準備
        CertificationListQueryDto dto = CertificationListQueryDto.builder()
                .names(List.of("基本情報技術者", "応用情報技術者", "AWS SAA"))
                .build();

        // モック設定
        when(certificationListQuery.findAll()).thenReturn(dto);

        // 実行&検証
        mockMvc.perform(get(ENDPOINT))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.names[0]").value("基本情報技術者"))
                .andExpect(jsonPath("$.names[1]").value("応用情報技術者"))
                .andExpect(jsonPath("$.names[2]").value("AWS SAA"));

        verify(certificationListQuery).findAll();
    }

    @Test
    @DisplayName("資格が1件も存在しない場合、200と空リストがレスポンスとして返る")
    void test2() throws Exception {
        // 空リストのDTOを準備
        CertificationListQueryDto dto = CertificationListQueryDto.builder()
                .names(List.of())
                .build();

        // モック設定
        when(certificationListQuery.findAll()).thenReturn(dto);

        // 実行&検証
        mockMvc.perform(get(ENDPOINT))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.names").isEmpty());

        verify(certificationListQuery).findAll();
    }
}
