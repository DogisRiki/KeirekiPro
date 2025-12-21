package com.example.keirekipro.unit.infrastructure.query.certification;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.List;

import com.example.keirekipro.infrastructure.query.certification.CertificationDto;
import com.example.keirekipro.infrastructure.query.certification.CertificationMapper;
import com.example.keirekipro.infrastructure.query.certification.CertificationQuery;
import com.example.keirekipro.usecase.query.certification.dto.CertificationListItemDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class CertificationQueryTest {

    @Mock
    private CertificationMapper certificationMapper;

    @InjectMocks
    private CertificationQuery certificationQuery;

    @Test
    @DisplayName("資格マスタが1件も存在しない場合、空リストで返る")
    void test1() {
        // モック準備
        when(certificationMapper.selectAll()).thenReturn(List.of());

        // 実行
        CertificationListItemDto actual = certificationQuery.selectCertificationListItem();

        // 検証
        assertThat(actual).isNotNull();
        assertThat(actual.getNames()).isEmpty();

        verify(certificationMapper).selectAll();
    }

    @Test
    @DisplayName("資格が存在する場合、資格名一覧が正しく返る")
    void test2() {
        // モック準備
        List<CertificationDto> rows = List.of(
                createCertification("基本情報技術者"),
                createCertification("応用情報技術者"),
                createCertification("AWS SAA"));
        when(certificationMapper.selectAll()).thenReturn(rows);

        // 実行
        CertificationListItemDto actual = certificationQuery.selectCertificationListItem();

        // 検証
        assertThat(actual).isNotNull();
        assertThat(actual.getNames())
                .containsExactly("基本情報技術者", "応用情報技術者", "AWS SAA");

        verify(certificationMapper).selectAll();
    }

    /**
     * CertificationDtoを生成するヘルパーメソッド
     */
    private CertificationDto createCertification(String name) {
        CertificationDto dto = new CertificationDto();
        dto.setName(name);
        return dto;
    }
}
