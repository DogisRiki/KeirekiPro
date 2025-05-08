package com.example.keirekipro.presentation.security.jwt;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import lombok.Getter;
import lombok.Setter;

/**
 * JWT設定プロパティファイル
 */
@Component
@ConfigurationProperties(prefix = "jwt")
@Getter
@Setter
public class JwtProperties {

    /**
     * 署名に使用する秘密鍵
     */
    private String secret;

    /**
     * アクセストークンの有効期限
     */
    private double accessTokenValidityInMinutes;

    /**
     * リフレッシュトークンの有効期限
     */
    private double refreshTokenValidityInDays;
}
