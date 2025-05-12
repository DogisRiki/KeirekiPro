package com.example.keirekipro.unit.presentation.shared.utils;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

import java.util.Optional;

import com.example.keirekipro.presentation.shared.utils.CookieUtil;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;

@ExtendWith(MockitoExtension.class)
class CookieUtilTest {

    @Mock
    private HttpServletRequest request;

    @Test
    @DisplayName("指定したCookieが存在する場合、その値が返却されること")
    public void test1() {
        Cookie[] cookies = new Cookie[] {
                new Cookie("test-cookie", "test-value"),
                new Cookie("other-cookie", "other-value")
        };
        when(request.getCookies()).thenReturn(cookies);

        Optional<String> resultTestCookie = CookieUtil.getCookieValue(request, "test-cookie");
        Optional<String> resultOtherCookie = CookieUtil.getCookieValue(request, "other-cookie");

        assertThat(resultTestCookie).isPresent().contains("test-value");
        assertThat(resultOtherCookie).isPresent().contains("other-value");
    }

    @Test
    @DisplayName("指定したCookieが存在しない場合、空のOptionalが返却されること")
    public void test2() {
        Cookie[] cookies = new Cookie[] { new Cookie("other-cookie", "other-value") };

        when(request.getCookies()).thenReturn(cookies);

        Optional<String> result = CookieUtil.getCookieValue(request, "test-cookie");

        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("Cookieが全く存在しない場合、空のOptionalが返却されること")
    public void test3() {
        when(request.getCookies()).thenReturn(null);

        Optional<String> result = CookieUtil.getCookieValue(request, "test-cookie");

        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("isSecureCookieがtrueの場合、HttpOnly・Secure属性を有効にしたCookieが正しく生成されること")
    public void test4() {
        String result = CookieUtil.createHttpOnlyCookie("test-cookie", "test-value", true);

        assertThat(result)
                .contains("test-cookie=test-value")
                .contains("HttpOnly")
                .contains("Secure")
                .contains("SameSite=Lax")
                .contains("Path=/");
    }

    @Test
    @DisplayName("isSecureCookieがfalseの場合、HttpOnly属性のみ有効のCookieが正しく生成されること")
    public void test5() {
        String result = CookieUtil.createHttpOnlyCookie("test-cookie", "test-value", false);

        assertThat(result)
                .contains("test-cookie=test-value")
                .contains("HttpOnly")
                .doesNotContain("Secure")
                .contains("SameSite=Lax")
                .contains("Path=/");
    }

    @Test
    @DisplayName("deleteCookie: isSecureCookie=true の場合、有効期限0・Secure・HttpOnly属性付きで生成されること")
    public void test6() {
        String result = CookieUtil.deleteCookie("test-cookie", true);

        assertThat(result)
                .contains("test-cookie=")
                .contains("Max-Age=0")
                .contains("HttpOnly")
                .contains("Secure")
                .contains("SameSite=Lax")
                .contains("Path=/");
    }

    @Test
    @DisplayName("deleteCookie: isSecureCookie=false の場合、有効期限0・HttpOnly属性のみで生成されること")
    public void test7() {
        String result = CookieUtil.deleteCookie("test-cookie", false);

        assertThat(result)
                .contains("test-cookie=")
                .contains("Max-Age=0")
                .contains("HttpOnly")
                .doesNotContain("Secure")
                .contains("SameSite=Lax")
                .contains("Path=/");
    }
}
