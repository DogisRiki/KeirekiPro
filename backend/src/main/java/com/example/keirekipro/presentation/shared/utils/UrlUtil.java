package com.example.keirekipro.presentation.shared.utils;

import jakarta.servlet.http.HttpServletRequest;

/**
 * URLに関する共通処理を提供するユーティリティクラス
 */
public class UrlUtil {

    /**
     * 現在のリクエストからベースURLを取得する。
     *
     * @param request HTTPリクエスト
     * @return ベースURL（例：https://example.com / http://localhost:8080）
     */
    public static String getBaseUrl(HttpServletRequest request) {
        String scheme = request.getScheme();
        String serverName = request.getServerName();
        int serverPort = request.getServerPort();

        StringBuilder url = new StringBuilder();
        url.append(scheme).append("://").append(serverName);

        if ((serverPort != 80 && "http".equals(scheme)) || (serverPort != 443 && "https".equals(scheme))) {
            url.append(":").append(serverPort);
        }

        return url.toString();
    }
}
