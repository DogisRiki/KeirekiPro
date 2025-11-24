package com.example.keirekipro.unit.domain.model.resume;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.YearMonth;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Certification;
import com.example.keirekipro.shared.Notification;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class CertificationTest {

    @Test
    @DisplayName("新規構築用コンストラクタでインスタンス化する")
    void test1() {
        Notification notification = new Notification();
        Certification certification = Certification.create(notification, "基本情報技術者", YearMonth.of(2025, 1));

        assertThat(certification).isNotNull();
        assertThat(certification.getId()).isNotNull();
        assertThat(certification.getName()).isEqualTo("基本情報技術者");
        assertThat(certification.getDate()).isEqualTo(YearMonth.of(2025, 1));
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test2() {
        UUID id = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        Certification certification = Certification.reconstruct(id, "基本情報技術者", YearMonth.of(2025, 1));

        assertThat(certification).isNotNull();
        assertThat(certification.getId()).isEqualTo(id);
        assertThat(certification.getName()).isEqualTo("基本情報技術者");
        assertThat(certification.getDate()).isEqualTo(YearMonth.of(2025, 1));
    }

    @Test
    @DisplayName("資格名を変更する")
    void test3() {
        Notification notification = new Notification();
        Certification beforeCertification = Certification.create(notification, "基本情報技術者", YearMonth.of(2025, 1));
        Certification afteCertification = beforeCertification.changeName(notification, "応用情報技術者");

        assertThat(afteCertification.getName()).isEqualTo("応用情報技術者");
    }

    @Test
    @DisplayName("取得年月を変更する")
    void test4() {
        Notification notification = new Notification();
        Certification beforeCertification = Certification.create(notification, "基本情報技術者", YearMonth.of(2025, 1));
        Certification afteCertification = beforeCertification.changeDate(notification, YearMonth.of(2030, 1));

        assertThat(afteCertification.getDate()).isEqualTo(YearMonth.of(2030, 1));
    }

    @Test
    @DisplayName("資格名、取得年月を変更する")
    void test5() {
        Notification notification = new Notification();
        Certification beforeCertification = Certification.create(notification, "基本情報技術者", YearMonth.of(2025, 1));
        Certification afteCertification = beforeCertification.changeDate(notification, YearMonth.of(2030, 1))
                .changeName(notification, "応用情報技術者");

        assertThat(afteCertification.getDate()).isEqualTo(YearMonth.of(2030, 1));
        assertThat(afteCertification.getName()).isEqualTo("応用情報技術者");
    }

    @Test
    @DisplayName("必須項目が未入力の場合、エラーが通知される")
    void test6() {
        Notification notification = new Notification();

        Certification.create(notification, "", null);

        assertThat(notification.getErrors().get("name")).containsExactly("資格名は入力必須です。");
        assertThat(notification.getErrors().get("date")).containsExactly("取得年月は入力必須です。");
    }

    @Test
    @DisplayName("資格名が最大文字数を超える場合、エラーが通知される")
    void test7() {
        Notification notification = new Notification();
        String longName = "a".repeat(51);

        Certification.create(notification, longName, YearMonth.of(2025, 1));

        assertThat(notification.getErrors().get("name")).containsExactly("資格名は50文字以内で入力してください。");
    }
}
