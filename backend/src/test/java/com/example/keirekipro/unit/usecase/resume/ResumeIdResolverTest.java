package com.example.keirekipro.unit.usecase.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.UUID;

import com.example.keirekipro.usecase.resume.ResumeIdResolver;
import com.example.keirekipro.usecase.shared.exception.ResourceNotFoundUseCaseException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class ResumeIdResolverTest {

    @Test
    @DisplayName("UUID形式の職務経歴書リソースIDを内部IDへ解決できる")
    void test1() {
        String resumeId = "22222222-2222-2222-2222-222222222222";

        assertThat(ResumeIdResolver.resolve(resumeId)).isEqualTo(UUID.fromString(resumeId));
    }

    @Test
    @DisplayName("UUID形式でない職務経歴書リソースIDは不存在として扱う")
    void test2() {
        assertThatThrownBy(() -> ResumeIdResolver.resolve("not-a-uuid"))
                .isInstanceOf(ResourceNotFoundUseCaseException.class)
                .hasMessage("対象の職務経歴書データが存在しません。");
    }
}
