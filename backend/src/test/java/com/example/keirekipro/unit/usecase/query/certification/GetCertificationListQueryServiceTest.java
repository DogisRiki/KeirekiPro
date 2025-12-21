package com.example.keirekipro.unit.usecase.query.certification;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.example.keirekipro.infrastructure.query.certification.CertificationQuery;
import com.example.keirekipro.usecase.query.certification.GetCertificationListQueryService;
import com.example.keirekipro.usecase.query.certification.dto.CertificationListItemDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class GetCertificationListQueryServiceTest {

    @Mock
    private CertificationQuery certificationQuery;

    @InjectMocks
    private GetCertificationListQueryService service;

    @Test
    @DisplayName("CertificationQueryの結果をそのまま返却する")
    void test1() {
        // モック準備
        CertificationListItemDto expected = CertificationListItemDto.create(java.util.List.of());
        when(certificationQuery.selectCertificationListItem()).thenReturn(expected);

        // 実行
        CertificationListItemDto actual = service.execute();

        // 検証
        assertThat(actual).isSameAs(expected);
        verify(certificationQuery).selectCertificationListItem();
    }
}
