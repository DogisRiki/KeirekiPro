package com.example.keirekipro.unit.presentation.shared.utils;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

import com.example.keirekipro.presentation.shared.utils.UrlUtil;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import jakarta.servlet.http.HttpServletRequest;

@ExtendWith(MockitoExtension.class)
class UrlUtilTest {

    @Mock
    private HttpServletRequest request;

    @Test
    @DisplayName("HTTP標準ポート80の場合、ポート番号なしのURLが返却されること")
    public void test1() {
        // モックをセットアップ
        when(request.getScheme()).thenReturn("http");
        when(request.getServerName()).thenReturn("example.com");
        when(request.getServerPort()).thenReturn(80);

        String result = UrlUtil.getBaseUrl(request);

        assertThat(result).isEqualTo("http://example.com");
    }

    @Test
    @DisplayName("HTTPS標準ポート443の場合、ポート番号なしのURLが返却されること")
    public void test2() {
        // モックをセットアップ
        when(request.getScheme()).thenReturn("https");
        when(request.getServerName()).thenReturn("example.com");
        when(request.getServerPort()).thenReturn(443);

        String result = UrlUtil.getBaseUrl(request);

        assertThat(result).isEqualTo("https://example.com");
    }

    @Test
    @DisplayName("HTTP非標準ポート8080の場合、ポート番号付きのURLが返却されること")
    public void test3() {
        // モックをセットアップ
        when(request.getScheme()).thenReturn("http");
        when(request.getServerName()).thenReturn("example.com");
        when(request.getServerPort()).thenReturn(8080);

        String result = UrlUtil.getBaseUrl(request);

        assertThat(result).isEqualTo("http://example.com:8080");
    }

    @Test
    @DisplayName("HTTPS非標準ポート8443の場合、ポート番号付きのURLが返却されること")
    public void test4() {
        // モックをセットアップ
        when(request.getScheme()).thenReturn("https");
        when(request.getServerName()).thenReturn("example.com");
        when(request.getServerPort()).thenReturn(8443);

        String result = UrlUtil.getBaseUrl(request);

        assertThat(result).isEqualTo("https://example.com:8443");
    }

    @Test
    @DisplayName("ローカル環境のlocalhost:8080の場合、正しいURLが返却されること")
    public void test5() {
        // モックをセットアップ
        when(request.getScheme()).thenReturn("http");
        when(request.getServerName()).thenReturn("localhost");
        when(request.getServerPort()).thenReturn(8080);

        String result = UrlUtil.getBaseUrl(request);

        assertThat(result).isEqualTo("http://localhost:8080");
    }
}
