package com.example.keirekipro.infrastructure.shared.thymeleaf;

import java.nio.charset.StandardCharsets;
import java.util.Set;

import org.springframework.context.ApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.thymeleaf.spring6.templateresolver.SpringResourceTemplateResolver;
import org.thymeleaf.templatemode.TemplateMode;

/**
 * Thymeleaf設定
 */
@Configuration
public class ThymeleafTemplateConfig {

    /**
     * MarkdownテンプレートをThymeleafでTEXTとして解決するためのTemplateResolver
     */
    @Bean
    public SpringResourceTemplateResolver resumeMarkdownTemplateResolver(ApplicationContext applicationContext) {
        SpringResourceTemplateResolver resolver = new SpringResourceTemplateResolver();
        resolver.setApplicationContext(applicationContext);

        resolver.setPrefix("classpath:/templates/");
        resolver.setSuffix(".md");
        resolver.setTemplateMode(TemplateMode.TEXT);
        resolver.setCharacterEncoding(StandardCharsets.UTF_8.name());

        // Markdownテンプレートのみを解決対象にして、他テンプレート（HTML等）の解決に影響させない
        resolver.setResolvablePatterns(Set.of("resume/markdown/*"));

        // Markdownテンプレートの存在確認を有効化し、不要な例外発生を抑制する
        resolver.setCheckExistence(true);

        // 既定のHTML向けresolverより先に評価されるよう優先順位を設定する（小さいほど優先）
        resolver.setOrder(0);

        return resolver;
    }
}
