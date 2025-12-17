package com.example.keirekipro.unit.domain.model.resume;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.SelfPromotion;
import com.example.keirekipro.shared.Notification;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class SelfPromotionTest {

    @Mock
    private Notification notification;

    @Test
    @DisplayName("新規構築用コンストラクタでインスタンス化する")
    void test1() {
        SelfPromotion selfPromotion = SelfPromotion.create(notification, "タイトル", "自己PRコンテンツ");

        assertThat(selfPromotion).isNotNull();
        assertThat(selfPromotion.getId()).isNotNull();
        assertThat(selfPromotion.getTitle()).isEqualTo("タイトル");
        assertThat(selfPromotion.getContent()).isEqualTo("自己PRコンテンツ");
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test2() {
        UUID id = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        SelfPromotion selfPromotion = SelfPromotion.reconstruct(id, "タイトル", "自己PRコンテンツ");

        assertThat(selfPromotion).isNotNull();
        assertThat(selfPromotion.getId()).isEqualTo(id);
        assertThat(selfPromotion.getTitle()).isEqualTo("タイトル");
        assertThat(selfPromotion.getContent()).isEqualTo("自己PRコンテンツ");
    }

    @Test
    @DisplayName("タイトルを変更する")
    void test3() {
        SelfPromotion beforeSelfPromotion = SelfPromotion.create(notification, "タイトル", "自己PRコンテンツ");
        SelfPromotion afterSelfPromotion = beforeSelfPromotion.changeTitle(notification, "新しいタイトル");

        assertThat(afterSelfPromotion.getTitle()).isEqualTo("新しいタイトル");
    }

    @Test
    @DisplayName("コンテンツを変更する")
    void test4() {
        SelfPromotion beforeSelfPromotion = SelfPromotion.create(notification, "タイトル", "自己PRコンテンツ");
        SelfPromotion afterSelfPromotion = beforeSelfPromotion.changeContent(notification, "新しい自己PRコンテンツ");

        assertThat(afterSelfPromotion.getContent()).isEqualTo("新しい自己PRコンテンツ");
    }

    @Test
    @DisplayName("タイトル、コンテンツを変更する")
    void test5() {
        SelfPromotion beforeSelfPromotion = SelfPromotion.create(notification, "タイトル", "自己PRコンテンツ");
        SelfPromotion afterSelfPromotion = beforeSelfPromotion.changeContent(notification, "新しい自己PRコンテンツ")
                .changeTitle(notification, "新しいタイトル");

        assertThat(afterSelfPromotion.getContent()).isEqualTo("新しい自己PRコンテンツ");
        assertThat(afterSelfPromotion.getTitle()).isEqualTo("新しいタイトル");
    }

    @Test
    @DisplayName("必須項目が未入力の場合、エラーが通知される")
    void test6() {
        Notification notification = new Notification();

        SelfPromotion.create(notification, "", "");

        assertThat(notification.getErrors().get("title"))
                .containsExactly("タイトルは入力必須です。");
        assertThat(notification.getErrors().get("content"))
                .containsExactly("コンテンツは入力必須です。");
    }

    @Test
    @DisplayName("各項目が最大文字数を超える場合、エラーが通知される")
    void test7() {
        Notification notification = new Notification();
        String longTitle = "a".repeat(51);
        String longContent = "a".repeat(1001);

        SelfPromotion.create(notification, longTitle, longContent);

        assertThat(notification.getErrors().get("title"))
                .containsExactly("タイトルは50文字以内で入力してください。");
        assertThat(notification.getErrors().get("content"))
                .containsExactly("コンテンツは1000文字以内で入力してください。");
    }
}
