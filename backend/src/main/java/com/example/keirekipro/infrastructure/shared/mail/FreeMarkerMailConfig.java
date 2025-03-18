package com.example.keirekipro.infrastructure.shared.mail;

import java.io.IOException;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import freemarker.template.TemplateException;
import freemarker.template.TemplateExceptionHandler;

/**
 * FreeMarker設定クラス
 */
@Configuration
public class FreeMarkerMailConfig {
    @Bean
    freemarker.template.Configuration freemarkerConfiguration() throws IOException, TemplateException {
        var conf = new freemarker.template.Configuration(freemarker.template.Configuration.VERSION_2_3_34);
        conf.setClassForTemplateLoading(this.getClass(), "/mail/");
        conf.setDefaultEncoding("UTF-8");
        conf.setTemplateExceptionHandler(TemplateExceptionHandler.RETHROW_HANDLER);
        return conf;
    }
}
