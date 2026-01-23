package com.example.keirekipro.unit.presentation.shared.utils;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.example.keirekipro.presentation.shared.utils.DevBaseUrlResolver;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import jakarta.servlet.http.HttpServletRequest;

/**
 * DevBaseUrlResolverのユニットテスト
 */
class DevBaseUrlResolverTest {

    private HttpServletRequest request;
    private DevBaseUrlResolver resolver;

    @BeforeEach
    void setUp() {
        request = mock(HttpServletRequest.class);
        resolver = new DevBaseUrlResolver();
    }

    @Test
    @DisplayName("HTTP標準ポートの場合、ポート番号なしでURLが構築される")
    void buildsUrlWithoutPortForHttp80() {
        // Arrange
        when(request.getScheme()).thenReturn("http");
        when(request.getServerName()).thenReturn("localhost");
        when(request.getServerPort()).thenReturn(80);

        // Act
        String result = resolver.resolve(request);

        // Assert
        assertThat(result).isEqualTo("http://localhost");
    }

    @Test
    @DisplayName("HTTPS標準ポートの場合、ポート番号なしでURLが構築される")
    void buildsUrlWithoutPortForHttps443() {
        // Arrange
        when(request.getScheme()).thenReturn("https");
        when(request.getServerName()).thenReturn("localhost");
        when(request.getServerPort()).thenReturn(443);

        // Act
        String result = resolver.resolve(request);

        // Assert
        assertThat(result).isEqualTo("https://localhost");
    }

    @Test
    @DisplayName("非標準ポートの場合、ポート番号付きでURLが構築される")
    void buildsUrlWithPortForNonStandardPort() {
        // Arrange
        when(request.getScheme()).thenReturn("http");
        when(request.getServerName()).thenReturn("localhost");
        when(request.getServerPort()).thenReturn(8080);

        // Act
        String result = resolver.resolve(request);

        // Assert
        assertThat(result).isEqualTo("http://localhost:8080");
    }
}
