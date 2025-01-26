package com.example.keirekipro.domain.resume;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.SelfPromotion;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class SelfPromotionTest {

    @Test
    @DisplayName("新規構築用コンストラクタでインスタンス化する")
    void test1() {
        SelfPromotion selfPromotion = SelfPromotion.create(0, "タイトル", "自己PRコンテンツ");
        // インスタンスがnullでない。
        assertNotNull(selfPromotion);
        // idが生成されている。
        assertNotNull(selfPromotion.getId());
        // 並び順が正しい値である。
        assertEquals(0, selfPromotion.getOrderNo());
        // タイトルが正しい値である。
        assertEquals("タイトル", selfPromotion.getTitle());
        // コンテンツが正しい値である。
        assertEquals("自己PRコンテンツ", selfPromotion.getContent());
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test2() {
        UUID id = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        SelfPromotion selfPromotion = SelfPromotion.reconstruct(id, 0, "タイトル", "自己PRコンテンツ");
        // インスタンスがnullでない。
        assertNotNull(selfPromotion);
        // idが正しい値である。
        assertEquals(selfPromotion.getId(), "1234");
        // 並び順が正しい値である。
        assertEquals(selfPromotion.getOrderNo(), 0);
        // タイトルが正しい値である。
        assertEquals(selfPromotion.getTitle(), "タイトル");
        // コンテンツが正しい値である。
        assertEquals(selfPromotion.getContent(), "自己PRコンテンツ");
    }

    @Test
    @DisplayName("タイトルを変更する")
    void test3() {
        SelfPromotion beforeSelfPromotion = SelfPromotion.create(0, "タイトル", "自己PRコンテンツ");
        SelfPromotion afterSelfPromotion = beforeSelfPromotion.changeTitle("新しいタイトル");
        // 変更したタイトルが正しい値である。
        assertEquals(afterSelfPromotion.getTitle(), "新しいタイトル");
    }

    @Test
    @DisplayName("コンテンツを変更する")
    void test4() {
        SelfPromotion beforeSelfPromotion = SelfPromotion.create(0, "タイトル", "自己PRコンテンツ");
        SelfPromotion afterSelfPromotion = beforeSelfPromotion.changeContent("新しい自己PRコンテンツ");
        // 変更したコンテンツが正しい値である。
        assertEquals(afterSelfPromotion.getContent(), "新しい自己PRコンテンツ");
    }

    @Test
    @DisplayName("タイトル、コンテンツを変更する")
    void test5() {
        SelfPromotion beforeSelfPromotion = SelfPromotion.create(0, "タイトル", "自己PRコンテンツ");
        SelfPromotion afterSelfPromotion = beforeSelfPromotion.changeContent("新しい自己PRコンテンツ")
                .changeTitle("新しいタイトル");
        // 変更した項目が正しい値である。
        assertEquals(afterSelfPromotion.getContent(), "新しい自己PRコンテンツ");
        assertEquals(afterSelfPromotion.getTitle(), "新しいタイトル");
    }
}
