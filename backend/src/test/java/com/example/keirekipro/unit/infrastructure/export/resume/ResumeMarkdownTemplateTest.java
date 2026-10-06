package com.example.keirekipro.unit.infrastructure.export.resume;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.thymeleaf.context.Context;
import org.thymeleaf.spring6.SpringTemplateEngine;
import org.thymeleaf.templatemode.TemplateMode;
import org.thymeleaf.templateresolver.ClassLoaderTemplateResolver;

/**
 * Markdownテンプレート(resume/markdown/default)の描画結果を検証する
 */
class ResumeMarkdownTemplateTest {

    private static final String TEMPLATE_NAME = "resume/markdown/default";

    private SpringTemplateEngine templateEngine;

    @BeforeEach
    void setUp() {
        ClassLoaderTemplateResolver resolver = new ClassLoaderTemplateResolver();
        resolver.setPrefix("templates/");
        resolver.setSuffix(".md");
        resolver.setTemplateMode(TemplateMode.TEXT);
        resolver.setCharacterEncoding(StandardCharsets.UTF_8.name());

        templateEngine = new SpringTemplateEngine();
        templateEngine.setTemplateResolver(resolver);
    }

    @Test
    @DisplayName("技術スタックが空のポートフォリオには技術スタックの行を出力しない")
    void test1() {
        String markdown = render(portfolio("空のポートフォリオ", ""));

        assertThat(markdown).contains("**空のポートフォリオ**");
        assertThat(markdown).doesNotContain("技術スタック：");
    }

    @Test
    @DisplayName("技術スタックがnullのポートフォリオには技術スタックの行を出力しない")
    void test2() {
        String markdown = render(portfolio("技術スタック未設定のポートフォリオ", null));

        assertThat(markdown).contains("**技術スタック未設定のポートフォリオ**");
        assertThat(markdown).doesNotContain("技術スタック：");
    }

    @Test
    @DisplayName("技術スタックがあるポートフォリオには技術スタックの行を出力する")
    void test3() {
        String markdown = render(portfolio("技術スタックありのポートフォリオ", "Java, Spring Boot"));

        assertThat(markdown).contains("技術スタック：Java, Spring Boot");
    }

    private String render(Map<String, Object> portfolio) {
        Map<String, Object> export = new LinkedHashMap<>();
        export.put("title", "職務経歴書");
        export.put("asOfDateLabel", "2026年10月6日現在");
        export.put("fullName", "山田 太郎");
        export.put("careers", List.of());
        export.put("companySections", List.of());
        export.put("certifications", List.of());
        export.put("portfolios", List.of(portfolio));
        export.put("snsPlatforms", List.of());
        export.put("selfPromotions", List.of());

        Context context = new Context();
        context.setVariable("export", export);
        return templateEngine.process(TEMPLATE_NAME, context);
    }

    private static Map<String, Object> portfolio(String name, String techStack) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("name", name);
        m.put("url", "https://example.com");
        m.put("techStack", techStack);
        m.put("overview", "概要");
        return m;
    }
}
