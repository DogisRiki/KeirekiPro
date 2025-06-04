package com.example.keirekipro.infrastructure.shared.mail;

import java.io.StringWriter;
import java.util.Map;

import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

import freemarker.template.Configuration;
import freemarker.template.Template;

/**
 * メールテンプレートクラス
 */
@Component
@RequiredArgsConstructor
public class FreeMarkerMailTemplate {

    private final Configuration freeMarkerConfiguration;

    /**
     * 指定したテンプレートファイルにdataModelを差し込み、メール本文テキストを生成する
     *
     * @param templateName テンプレートファイル名(ftl)
     * @param dataModel    プレースホルダーにマッピングするMapオブジェクト
     * @return メール本文テキスト
     */
    public String create(String templateName, Map<String, Object> dataModel) {
        try {
            Template template = freeMarkerConfiguration.getTemplate(templateName);
            StringWriter writer = new StringWriter();
            template.process(dataModel, writer);
            return writer.toString();
        } catch (Exception e) {
            throw new RuntimeException("FreeMarkerテンプレート処理に失敗: " + templateName, e);
        }
    }
}
