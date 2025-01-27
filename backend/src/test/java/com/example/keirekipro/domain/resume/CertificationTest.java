package com.example.keirekipro.domain.resume;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.time.YearMonth;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Certification;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class CertificationTest {

    @Test
    @DisplayName("新規構築用コンストラクタでインスタンス化する")
    void test1() {
        Certification certification = Certification.create(0, "基本情報技術者", YearMonth.of(2025, 01));
        // インスタンスがnullでない。
        assertNotNull(certification);
        // idが生成されている。
        assertNotNull(certification.getId());
        // 並び順が正しい値である。
        assertEquals(0, certification.getOrderNo());
        // 資格名が正しい値である。
        assertEquals("基本情報技術者", certification.getName());
        // 取得年月が正しい値である。
        assertEquals(YearMonth.of(2025, 01), certification.getDate());
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test2() {
        UUID id = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        Certification certification = Certification.reconstruct(id, 0, "基本情報技術者", YearMonth.of(2025, 01));
        // インスタンスがnullでない。
        assertNotNull(certification);
        // idが正しい値である。
        assertEquals(certification.getId(), id);
        // 並び順が正しい値である。
        assertEquals(0, certification.getOrderNo());
        // 資格名が正しい値である。
        assertEquals("基本情報技術者", certification.getName());
        // 取得年月が正しい値である。
        assertEquals(YearMonth.of(2025, 01), certification.getDate());
    }

    @Test
    @DisplayName("資格名を変更する")
    void test3() {
        Certification beforeCertification = Certification.create(0, "基本情報技術者", YearMonth.of(2025, 01));
        Certification afteCertification = beforeCertification.changeName("応用情報技術者");
        // 変更した資格名が正しい値である。
        assertEquals(afteCertification.getName(), "応用情報技術者");
    }

    @Test
    @DisplayName("取得年月を変更する")
    void test4() {
        Certification beforeCertification = Certification.create(0, "基本情報技術者", YearMonth.of(2025, 01));
        Certification afteCertification = beforeCertification.changeDate(YearMonth.of(2030, 01));
        // 変更した取得年月が正しい値である。
        assertEquals(afteCertification.getDate(), YearMonth.of(2030, 01));
    }

    @Test
    @DisplayName("資格名、取得年月を変更する")
    void test5() {
        Certification beforeCertification = Certification.create(0, "基本情報技術者", YearMonth.of(2025, 01));
        Certification afteCertification = beforeCertification.changeDate(YearMonth.of(2030, 01)).changeName("応用情報技術者");
        // 変更した項目が正しい値である。
        assertEquals(afteCertification.getDate(), YearMonth.of(2030, 01));
        assertEquals(afteCertification.getName(), "応用情報技術者");
    }
}
