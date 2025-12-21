package com.example.keirekipro.unit.usecase.query.snsplatform;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.example.keirekipro.infrastructure.query.snsplatform.SnsPlatformQuery;
import com.example.keirekipro.usecase.query.snsplatform.GetSnsPlatformListQueryService;
import com.example.keirekipro.usecase.query.snsplatform.dto.SnsPlatformListItemDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class GetSnsPlatformListQueryServiceTest {

    @Mock
    private SnsPlatformQuery snsPlatformQuery;

    @InjectMocks
    private GetSnsPlatformListQueryService service;

    @Test
    @DisplayName("SnsPlatformQueryの結果をそのまま返却する")
    void test1() {
        // モック準備
        SnsPlatformListItemDto expected = SnsPlatformListItemDto.create(java.util.List.of());
        when(snsPlatformQuery.selectSnsPlatformListItem()).thenReturn(expected);

        // 実行
        SnsPlatformListItemDto actual = service.execute();

        // 検証
        assertThat(actual).isSameAs(expected);
        verify(snsPlatformQuery).selectSnsPlatformListItem();
    }
}
