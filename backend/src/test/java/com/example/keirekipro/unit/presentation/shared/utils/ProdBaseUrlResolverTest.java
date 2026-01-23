package com.example.keirekipro.unit.presentation.shared.utils;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import com.example.keirekipro.presentation.shared.utils.ProdBaseUrlResolver;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import jakarta.servlet.http.HttpServletRequest;

/**
 * ProdBaseUrlResolverのユニットテスト
 */
class ProdBaseUrlResolverTest {

    @Test
    @DisplayName("設定値がそのまま返却される")
    void returnsConfiguredUrl() {
        // Arrange
        ProdBaseUrlResolver resolver = new ProdBaseUrlResolver("https://app.keirekipro.click");
        HttpServletRequest request = mock(HttpServletRequest.class);

        // Act
        String result = resolver.resolve(request);

        // Assert
        assertThat(result).isEqualTo("https://app.keirekipro.click");
    }
}
