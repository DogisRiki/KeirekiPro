package com.example.keirekipro.unit.domain.model.resume;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.YearMonth;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Certification;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class CertificationTest {

    @Test
    @DisplayName("新規構築用コンストラクタでインスタンス化する")
    void test1() {
        Certification certification = Certification.create("基本情報技術者", YearMonth.of(2025, 01));

        assertThat(certification).isNotNull();
        assertThat(certification.getId()).isNotNull();
        assertThat(certification.getName()).isEqualTo("基本情報技術者");
        assertThat(certification.getDate()).isEqualTo(YearMonth.of(2025, 01));
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test2() {
        UUID id = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        Certification certification = Certification.reconstruct(id, "基本情報技術者", YearMonth.of(2025, 01));

        assertThat(certification).isNotNull();
        assertThat(certification.getId()).isEqualTo(id);
        assertThat(certification.getName()).isEqualTo("基本情報技術者");
        assertThat(certification.getDate()).isEqualTo(YearMonth.of(2025, 01));
    }

    @Test
    @DisplayName("資格名を変更する")
    void test3() {
        Certification beforeCertification = Certification.create("基本情報技術者", YearMonth.of(2025, 01));
        Certification afteCertification = beforeCertification.changeName("応用情報技術者");

        assertThat(afteCertification.getName()).isEqualTo("応用情報技術者");
    }

    @Test
    @DisplayName("取得年月を変更する")
    void test4() {
        Certification beforeCertification = Certification.create("基本情報技術者", YearMonth.of(2025, 01));
        Certification afteCertification = beforeCertification.changeDate(YearMonth.of(2030, 01));

        assertThat(afteCertification.getDate()).isEqualTo(YearMonth.of(2030, 01));
    }

    @Test
    @DisplayName("資格名、取得年月を変更する")
    void test5() {
        Certification beforeCertification = Certification.create("基本情報技術者", YearMonth.of(2025, 01));
        Certification afteCertification = beforeCertification.changeDate(YearMonth.of(2030, 01)).changeName("応用情報技術者");

        assertThat(afteCertification.getDate()).isEqualTo(YearMonth.of(2030, 01));
        assertThat(afteCertification.getName()).isEqualTo("応用情報技術者");
    }
}
