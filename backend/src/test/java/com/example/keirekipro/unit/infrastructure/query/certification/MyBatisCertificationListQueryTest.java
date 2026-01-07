package com.example.keirekipro.unit.infrastructure.query.certification;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.List;

import com.example.keirekipro.infrastructure.query.certification.CertificationQueryMapper;
import com.example.keirekipro.infrastructure.query.certification.MyBatisCertificationListQuery;
import com.example.keirekipro.usecase.query.certification.dto.CertificationListQueryDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class MyBatisCertificationListQueryTest {

    @Mock
    private CertificationQueryMapper certificationQueryMapper;

    @InjectMocks
    private MyBatisCertificationListQuery myBatisCertificationListQuery;

    @Test
    @DisplayName("資格マスタが1件も存在しない場合、空リストで返る")
    void test1() {
        // モック準備
        when(certificationQueryMapper.selectAll()).thenReturn(List.of());

        // 実行
        CertificationListQueryDto actual = myBatisCertificationListQuery.findAll();

        // 検証
        assertThat(actual).isNotNull();
        assertThat(actual.getNames()).isEmpty();

        verify(certificationQueryMapper).selectAll();
    }

    @Test
    @DisplayName("資格が存在する場合、資格名一覧が正しく返る")
    void test2() {
        // モック準備
        List<CertificationQueryMapper.CertificationRow> rows = List.of(
                createCertificationRow("基本情報技術者"),
                createCertificationRow("応用情報技術者"),
                createCertificationRow("AWS SAA"));
        when(certificationQueryMapper.selectAll()).thenReturn(rows);

        // 実行
        CertificationListQueryDto actual = myBatisCertificationListQuery.findAll();

        // 検証
        assertThat(actual).isNotNull();
        assertThat(actual.getNames())
                .containsExactly("基本情報技術者", "応用情報技術者", "AWS SAA");

        verify(certificationQueryMapper).selectAll();
    }

    /**
     * CertificationRowを生成するヘルパーメソッド
     */
    private CertificationQueryMapper.CertificationRow createCertificationRow(String name) {
        CertificationQueryMapper.CertificationRow row = new CertificationQueryMapper.CertificationRow();
        row.setName(name);
        return row;
    }
}
