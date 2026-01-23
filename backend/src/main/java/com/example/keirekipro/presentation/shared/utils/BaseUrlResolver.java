package com.example.keirekipro.presentation.shared.utils;

import jakarta.servlet.http.HttpServletRequest;

/**
 * APIのベースURLを解決するインターフェース
 */
public interface BaseUrlResolver {

    /**
     * APIのベースURLを取得する
     *
     * @param request HTTPリクエスト
     * @return ベースURL
     */
    String resolve(HttpServletRequest request);
}
