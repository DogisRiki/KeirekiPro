package com.example.keirekipro.unit.infrastructure.shared.aws.s3;

import static org.assertj.core.api.Assertions.assertThat;

import com.example.keirekipro.infrastructure.shared.aws.s3.NoopPresignedUrlTransformer;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class NoopPresignedUrlTransformerTest {

    @Test
    @DisplayName("NoopはURLをそのまま返す")
    void test1() {
        NoopPresignedUrlTransformer transformer = new NoopPresignedUrlTransformer();
        assertThat(transformer.transform("https://example.com/a")).isEqualTo("https://example.com/a");
    }
}
