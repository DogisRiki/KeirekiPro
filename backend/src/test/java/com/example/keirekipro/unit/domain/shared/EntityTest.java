package com.example.keirekipro.unit.domain.shared;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.UUID;

import com.example.keirekipro.domain.shared.Entity;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class EntityTest {

    // テスト用具体クラス
    private static class TestEntity extends Entity {
        public TestEntity() {
            super();
        }

        public TestEntity(UUID id) {
            super(id);
        }
    }

    @Test
    @DisplayName("新規構築用コンストラクタでインスタンス化する")
    void test1() {
        TestEntity entity = new TestEntity();
        assertThat(entity.getId()).isNotNull();
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test2() {
        UUID id = UUID.fromString("5af48f3b-468b-4ae0-a065-7d7ac70b37a8");
        TestEntity entity = new TestEntity(id);
        assertThat(entity.getId()).isEqualTo(id);
    }

    @Test
    @DisplayName("等価チェック")
    void test3() {
        UUID id1 = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        UUID id2 = UUID.fromString("123e4567-e89b-12d3-a456-426614174001");
        TestEntity entity1 = new TestEntity(id1);
        TestEntity entity2 = new TestEntity(id1);
        TestEntity entity3 = new TestEntity(id2);

        assertThat(entity1)
                .isEqualTo(entity2)
                .isNotEqualTo(entity3);
    }

    @Test
    @DisplayName("ハッシュ値")
    void test4() {
        UUID id1 = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        UUID id2 = UUID.fromString("123e4567-e89b-12d3-a456-426614174001");
        int entity1HashCode = new TestEntity(id1).hashCode();
        int entity2HashCode = new TestEntity(id1).hashCode();
        int entity3HashCode = new TestEntity(id2).hashCode();

        assertThat(entity1HashCode)
                .isEqualTo(entity2HashCode)
                .isNotEqualTo(entity3HashCode);
    }
}
