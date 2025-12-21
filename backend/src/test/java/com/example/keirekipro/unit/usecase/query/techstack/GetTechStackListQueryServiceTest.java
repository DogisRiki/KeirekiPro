package com.example.keirekipro.unit.usecase.query.techstack;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.example.keirekipro.infrastructure.query.techstack.TechStackQuery;
import com.example.keirekipro.usecase.query.techstack.GetTechStackListQueryService;
import com.example.keirekipro.usecase.query.techstack.dto.TechStackListItemDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class GetTechStackListQueryServiceTest {

    @Mock
    private TechStackQuery techStackQuery;

    @InjectMocks
    private GetTechStackListQueryService service;

    @Test
    @DisplayName("TechStackQueryの結果をそのまま返却する")
    void test1() {
        // モック準備
        TechStackListItemDto expected = TechStackListItemDto.create(
                TechStackListItemDto.Frontend.create(
                        java.util.List.of(), java.util.List.of(), java.util.List.of(), java.util.List.of(),
                        java.util.List.of(), java.util.List.of(), java.util.List.of(), java.util.List.of()),
                TechStackListItemDto.Backend.create(
                        java.util.List.of(), java.util.List.of(), java.util.List.of(), java.util.List.of(),
                        java.util.List.of(), java.util.List.of(), java.util.List.of(), java.util.List.of(),
                        java.util.List.of(), java.util.List.of()),
                TechStackListItemDto.Infrastructure.create(
                        java.util.List.of(), java.util.List.of(), java.util.List.of(), java.util.List.of(),
                        java.util.List.of(), java.util.List.of(), java.util.List.of(), java.util.List.of(),
                        java.util.List.of()),
                TechStackListItemDto.Tools.create(
                        java.util.List.of(), java.util.List.of(), java.util.List.of(), java.util.List.of(),
                        java.util.List.of(), java.util.List.of(), java.util.List.of(), java.util.List.of()));

        when(techStackQuery.selectTechStackListItem()).thenReturn(expected);

        // 実行
        TechStackListItemDto actual = service.execute();

        // 検証
        assertThat(actual).isSameAs(expected);
        verify(techStackQuery).selectTechStackListItem();
    }
}
