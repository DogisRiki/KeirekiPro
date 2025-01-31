package com.example.keirekipro.domain.shared;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.util.UUID;

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
        // idがnullでない。
        assertNotNull(entity.getId());
        // 並び順が正しい値である。
        assertEquals(1, entity.getOrderNo());
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test2() {
        UUID id = UUID.fromString("5af48f3b-468b-4ae0-a065-7d7ac70b37a8");
        TestEntity entity = new TestEntity(id, 2);
        // idが正しい値である。
        assertEquals(entity.getId(), id);
        // 並び順が正しい値である。
        assertEquals(2, entity.getOrderNo());
    }

    @Test
    @DisplayName("並び順を変更する")
    void test3() {
        TestEntity entity = new TestEntity(1);
        entity.changeOrderNo(100);
        // 変更した並び順が正しい値である。
        assertEquals(100, entity.getOrderNo());
    }

    @Test
    @DisplayName("等価チェック")
    void test4() {
        UUID id1 = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        UUID id2 = UUID.fromString("123e4567-e89b-12d3-a456-426614174001");
        TestEntity entity1 = new TestEntity(id1, 1);
        TestEntity entity2 = new TestEntity(id1, 1);
        TestEntity entity3 = new TestEntity(id2, 1);
        // idが同値であれば等価である。
        assertEquals(entity1, entity2);
        // idが同値でなければ等価でない。
        assertNotEquals(entity1, entity3);
    }

    @Test
    @DisplayName("ハッシュ値")
    void test5() {
        UUID id1 = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        UUID id2 = UUID.fromString("123e4567-e89b-12d3-a456-426614174001");
        int entity1 = new TestEntity(id1, 1).hashCode();
        int entity2 = new TestEntity(id1, 1).hashCode();
        int entity3 = new TestEntity(id2, 1).hashCode();
        // idが同値であれば同一のハッシュ値である。
        assertEquals(entity1, entity2);
        // idが異なればハッシュ値も異なる。
        assertNotEquals(entity1, entity3);
    }
}
