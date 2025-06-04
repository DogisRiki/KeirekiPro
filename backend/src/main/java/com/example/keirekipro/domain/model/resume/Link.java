package com.example.keirekipro.domain.model.resume;

import java.net.URI;
import java.net.URISyntaxException;

import com.example.keirekipro.shared.Notification;

import lombok.EqualsAndHashCode;
import lombok.Getter;

/**
 * リンク
 */
@Getter
@EqualsAndHashCode
public class Link {

    private final String value;

    private Link(Notification notification, String value) {
        validate(notification, value);
        this.value = value;
    }

    /**
     * ファクトリーメソッド
     *
     * @param notification 通知オブジェクト
     * @param value        リンク
     * @return 値オブジェクト
     */
    public static Link create(Notification notification, String value) {
        return new Link(notification, value);
    }

    private void validate(Notification notification, String value) {
        if (isInvalidUrl(value)) {
            notification.addError("link", "無効なURLです。HTTPS形式で正しいURLを入力してください。");
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
