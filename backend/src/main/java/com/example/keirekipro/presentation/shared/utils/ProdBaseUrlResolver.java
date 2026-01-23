package com.example.keirekipro.presentation.shared.utils;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import jakarta.servlet.http.HttpServletRequest;

/**
 * 本番環境用のベースURL解決
 * 設定ファイルで指定されたベースURLを返す
 */
@Component
@Profile("prod")
public class ProdBaseUrlResolver implements BaseUrlResolver {

    private final String apiBaseUrl;

    /**
     * コンストラクタ
     */
    public ProdBaseUrlResolver(@Value("${app.api-base-url}") String apiBaseUrl) {
        this.apiBaseUrl = apiBaseUrl;
    }

    @Override
    public String resolve(HttpServletRequest request) {
        return apiBaseUrl;
    }
}
