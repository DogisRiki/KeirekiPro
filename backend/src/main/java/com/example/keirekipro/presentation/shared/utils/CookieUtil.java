package com.example.keirekipro.presentation.shared.utils;

import java.util.Arrays;
import java.util.Optional;

import org.springframework.http.ResponseCookie;

import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;

/**
 * Cookieに関する共通処理を提供するユーティリティクラス
 */
public class CookieUtil {

    /**
     * リクエストから指定した名前のCookieの値を取得する
     *
     * @param request HTTPリクエスト
     * @param name    取得したいCookieの名前
     * @return 該当するCookieの値。存在しない場合はOptional.empty()を返す。
     */
    public static Optional<String> getCookieValue(HttpServletRequest request, String name) {
        if (request.getCookies() == null) {
            return Optional.empty();
        }
        return Arrays.stream(request.getCookies())
                .filter(cookie -> name.equals(cookie.getName()))
                .map(Cookie::getValue)
                .findFirst();
    }

    /**
     * HttpOnly属性・Secure属性付きのCookie文字列を生成する
     *
     * @param name           Cookieのキー
     * @param value          Cookieの値
     * @param isSecureCookie セキュア属性を有効にするかどうか
     * @return 生成されたCookie文字列
     */
    public static String createHttpOnlyCookie(String name, String value, boolean isSecureCookie) {
        return ResponseCookie.from(name, value)
                .httpOnly(true)
                .secure(isSecureCookie)
                .sameSite("Lax")
                .path("/")
                .build()
                .toString();
    }
}
