package com.example.keirekipro.presentation.shared.utils;

import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import jakarta.servlet.http.HttpServletRequest;

/**
 * 開発環境用のベースURL解決
 * リクエストから動的にベースURLを取得する
 *
 * test プロファイルでも有効にする。BaseUrlResolver の実装は dev と prod にしか無く、
 * 有効にしないとコンテキスト起動テストが組み上がらない。リクエストから解決する
 * 方式はテストでもそのまま成立する。
 */
@Component
@Profile({ "dev", "test" })
public class DevBaseUrlResolver implements BaseUrlResolver {

    @Override
    public String resolve(HttpServletRequest request) {
        String scheme = request.getScheme();
        String serverName = request.getServerName();
        int serverPort = request.getServerPort();

        StringBuilder url = new StringBuilder();
        url.append(scheme).append("://").append(serverName);

        if (isNonStandardPort(scheme, serverPort)) {
            url.append(":").append(serverPort);
        }

        return url.toString();
    }

    private boolean isNonStandardPort(String scheme, int port) {
        return ("http".equals(scheme) && port != 80)
                || ("https".equals(scheme) && port != 443);
    }
}
