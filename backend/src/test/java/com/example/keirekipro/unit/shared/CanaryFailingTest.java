package com.example.keirekipro.unit.shared;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/**
 * ゲート健康診断用のカナリア。意図的に失敗する。
 */
class CanaryFailingTest {

    @Test
    void 意図的に失敗するカナリアテスト() {
        assertThat(1 + 1).isEqualTo(3);
    }
}
