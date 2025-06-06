package com.example.keirekipro.unit.domain.shared;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.UUID;

import com.example.keirekipro.domain.shared.Entity;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class EntityTest {

    // テスト用具体クラス
    private static class TestEntity extends Entity {
        public TestEntity(int orderNo) {
            super(orderNo);
        }

        public TestEntity(UUID id, int orderNo) {
            super(id, orderNo);
        }
    }

    @Test
    @DisplayName("新規構築用コンストラクタでインスタンス化する")
    void test1() {
        TestEntity entity = new TestEntity(1);

        assertThat(entity.getId())
                .isNotNull();
        assertThat(entity.getOrderNo())
                .isEqualTo(1);
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test2() {
        UUID id = UUID.fromString("5af48f3b-468b-4ae0-a065-7d7ac70b37a8");
        TestEntity entity = new TestEntity(id, 2);

        assertThat(entity.getId())
                .isEqualTo(id);
        assertThat(entity.getOrderNo())
                .isEqualTo(2);
    }

    @Test
    @DisplayName("並び順を変更する")
    void test3() {
        TestEntity entity = new TestEntity(1);
        entity.changeOrderNo(100);

        assertThat(entity.getOrderNo())
                .isEqualTo(100);
    }

    @Test
    @DisplayName("等価チェック")
    void test4() {
        UUID id1 = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        UUID id2 = UUID.fromString("123e4567-e89b-12d3-a456-426614174001");
        TestEntity entity1 = new TestEntity(id1, 1);
        TestEntity entity2 = new TestEntity(id1, 1);
        TestEntity entity3 = new TestEntity(id2, 1);

        assertThat(entity1)
                .isEqualTo(entity2)
                .isNotEqualTo(entity3);
    }

    @Test
    @DisplayName("ハッシュ値")
    void test5() {
        UUID id1 = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        UUID id2 = UUID.fromString("123e4567-e89b-12d3-a456-426614174001");
        int entity1HashCode = new TestEntity(id1, 1).hashCode();
        int entity2HashCode = new TestEntity(id1, 1).hashCode();
        int entity3HashCode = new TestEntity(id2, 1).hashCode();

        assertThat(entity1HashCode)
                .isEqualTo(entity2HashCode)
                .isNotEqualTo(entity3HashCode);
    }
}
