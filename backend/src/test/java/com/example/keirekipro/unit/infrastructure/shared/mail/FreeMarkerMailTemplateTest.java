package com.example.keirekipro.unit.infrastructure.shared.mail;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.when;

import java.io.IOException;
import java.io.StringWriter;
import java.util.HashMap;

import com.example.keirekipro.infrastructure.shared.mail.FreeMarkerMailTemplate;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import freemarker.template.Configuration;
import freemarker.template.Template;

@ExtendWith(MockitoExtension.class)
class FreeMarkerMailTemplateTest {

    @Mock
    private Configuration freeMarkerConfiguration;

    @Mock
    private Template freeMarkerTemplate;

    private FreeMarkerMailTemplate freeMarkerMailTemplate;

    @BeforeEach
    void setUp() {
        freeMarkerMailTemplate = new FreeMarkerMailTemplate(freeMarkerConfiguration);
    }

    @Test
    @DisplayName("テンプレートを取得し、processでメール本文の文字列を生成できる")
    void create_success() throws Exception {
        // モックをセットアップ
        when(freeMarkerConfiguration.getTemplate("template.ftl")).thenReturn(freeMarkerTemplate);

        // template.process(...)を呼ぶと、Writerに"test"を書き込むシミュレーション
        doAnswer(invocation -> {
            StringWriter writer = invocation.getArgument(1, StringWriter.class);
            writer.write("test");
            return null;
        }).when(freeMarkerTemplate).process(anyMap(), any(StringWriter.class));

        // 実行
        String result = freeMarkerMailTemplate.create("template.ftl", new HashMap<>());

        // 検証
        assertThat(result)
                .isNotNull()
                .isEqualTo("test");
    }

    @Test
    @DisplayName("テンプレートが見つからない場合、RuntimeExceptionがスローされる")
    void create_templateNotFound() throws Exception {
        // モックをセットアップ
        when(freeMarkerConfiguration.getTemplate("ng.ftl"))
                .thenThrow(new IOException("Template not found"));

        assertThatThrownBy(() -> freeMarkerMailTemplate.create("ng.ftl", new HashMap<>()))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("ng.ftl");
    }
}
