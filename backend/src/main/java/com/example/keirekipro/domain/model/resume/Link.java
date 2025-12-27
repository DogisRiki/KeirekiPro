package com.example.keirekipro.domain.model.resume;

import java.net.URI;
import java.net.URISyntaxException;

import com.example.keirekipro.shared.ErrorCollector;

import lombok.EqualsAndHashCode;
import lombok.Getter;

/**
 * リンク
 */
@Getter
@EqualsAndHashCode
public class Link {

    private final String value;

    private Link(ErrorCollector errorCollector, String value) {
        validate(errorCollector, value);
        this.value = value;
    }

    /**
     * ファクトリーメソッド
     *
     * @param errorCollector エラー収集オブジェクト
     * @param value          リンク
     * @return 値オブジェクト
     */
    public static Link create(ErrorCollector errorCollector, String value) {
        return new Link(errorCollector, value);
    }

    private void validate(ErrorCollector errorCollector, String value) {
        if (value == null || value.isBlank()) {
            errorCollector.addError("link", "リンクは入力必須です。");
            return;
        }
        if (isInvalidUrl(value)) {
            errorCollector.addError("link", "無効なURLです。HTTPS形式で正しいURLを入力してください。");
        }
    }

    /**
     * 指定された文字列がRFC3986に準拠し、かつスキーマがhttpsであるかを検証する
     *
     * @param value リンク
     * @return 検証結果
     */
    private boolean isInvalidUrl(String value) {
        try {
            URI uri = new URI(value);
            return !"https".equalsIgnoreCase(uri.getScheme());
        } catch (URISyntaxException e) {
            return true;
        }
    }
}
