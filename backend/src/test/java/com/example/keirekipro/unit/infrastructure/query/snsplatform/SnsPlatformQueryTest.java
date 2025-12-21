package com.example.keirekipro.unit.infrastructure.query.snsplatform;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.List;

import com.example.keirekipro.infrastructure.query.snsplatform.SnsPlatformDto;
import com.example.keirekipro.infrastructure.query.snsplatform.SnsPlatformMapper;
import com.example.keirekipro.infrastructure.query.snsplatform.SnsPlatformQuery;
import com.example.keirekipro.usecase.query.snsplatform.dto.SnsPlatformListItemDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class SnsPlatformQueryTest {

    @Mock
    private SnsPlatformMapper snsPlatformMapper;

    @InjectMocks
    private SnsPlatformQuery snsPlatformQuery;

    @Test
    @DisplayName("SNSプラットフォームマスタが1件も存在しない場合、空リストで返る")
    void test1() {
        // モック準備
        when(snsPlatformMapper.selectAll()).thenReturn(List.of());

        // 実行
        SnsPlatformListItemDto actual = snsPlatformQuery.selectSnsPlatformListItem();

        // 検証
        assertThat(actual).isNotNull();
        assertThat(actual.getNames()).isEmpty();

        verify(snsPlatformMapper).selectAll();
    }

    @Test
    @DisplayName("SNSプラットフォームが存在する場合、プラットフォーム名一覧が正しく返る")
    void test2() {
        // モック準備
        List<SnsPlatformDto> rows = List.of(
                createSnsPlatform("X"),
                createSnsPlatform("Instagram"),
                createSnsPlatform("YouTube"));
        when(snsPlatformMapper.selectAll()).thenReturn(rows);

        // 実行
        SnsPlatformListItemDto actual = snsPlatformQuery.selectSnsPlatformListItem();

        // 検証
        assertThat(actual).isNotNull();
        assertThat(actual.getNames())
                .containsExactly("X", "Instagram", "YouTube");

        verify(snsPlatformMapper).selectAll();
    }

    /**
     * SnsPlatformDtoを生成するヘルパーメソッド
     */
    private SnsPlatformDto createSnsPlatform(String name) {
        SnsPlatformDto dto = new SnsPlatformDto();
        dto.setName(name);
        return dto;
    }
}
