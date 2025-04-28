package com.example.keirekipro.unit.domain.model.resume;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.SelfPromotion;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class SelfPromotionTest {

    @Test
    @DisplayName("新規構築用コンストラクタでインスタンス化する")
    void test1() {
        SelfPromotion selfPromotion = SelfPromotion.create(0, "タイトル", "自己PRコンテンツ");

        assertThat(selfPromotion).isNotNull();
        assertThat(selfPromotion.getId()).isNotNull();
        assertThat(selfPromotion.getOrderNo()).isEqualTo(0);
        assertThat(selfPromotion.getTitle()).isEqualTo("タイトル");
        assertThat(selfPromotion.getContent()).isEqualTo("自己PRコンテンツ");
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test2() {
        UUID id = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        SelfPromotion selfPromotion = SelfPromotion.reconstruct(id, 0, "タイトル", "自己PRコンテンツ");

        assertThat(selfPromotion).isNotNull();
        assertThat(selfPromotion.getId()).isEqualTo(id);
        assertThat(selfPromotion.getOrderNo()).isEqualTo(0);
        assertThat(selfPromotion.getTitle()).isEqualTo("タイトル");
        assertThat(selfPromotion.getContent()).isEqualTo("自己PRコンテンツ");
    }

    @Test
    @DisplayName("タイトルを変更する")
    void test3() {
        SelfPromotion beforeSelfPromotion = SelfPromotion.create(0, "タイトル", "自己PRコンテンツ");
        SelfPromotion afterSelfPromotion = beforeSelfPromotion.changeTitle("新しいタイトル");

        assertThat(afterSelfPromotion.getTitle()).isEqualTo("新しいタイトル");
    }

    @Test
    @DisplayName("コンテンツを変更する")
    void test4() {
        SelfPromotion beforeSelfPromotion = SelfPromotion.create(0, "タイトル", "自己PRコンテンツ");
        SelfPromotion afterSelfPromotion = beforeSelfPromotion.changeContent("新しい自己PRコンテンツ");

        assertThat(afterSelfPromotion.getContent()).isEqualTo("新しい自己PRコンテンツ");
    }

    @Test
    @DisplayName("タイトル、コンテンツを変更する")
    void test5() {
        SelfPromotion beforeSelfPromotion = SelfPromotion.create(0, "タイトル", "自己PRコンテンツ");
        SelfPromotion afterSelfPromotion = beforeSelfPromotion.changeContent("新しい自己PRコンテンツ")
                .changeTitle("新しいタイトル");

        assertThat(afterSelfPromotion.getContent()).isEqualTo("新しい自己PRコンテンツ");
        assertThat(afterSelfPromotion.getTitle()).isEqualTo("新しいタイトル");
    }
}
