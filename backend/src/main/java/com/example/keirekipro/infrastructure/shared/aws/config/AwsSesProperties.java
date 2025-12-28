package com.example.keirekipro.infrastructure.shared.aws.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import lombok.Getter;
import lombok.Setter;

/**
 * SES設定
 */
@Component
@Getter
@Setter
@ConfigurationProperties(prefix = "aws.ses")
public class AwsSesProperties {

    /**
     * リージョン
     */
    private String region;

    /**
     * エンドポイントURL（devのみ）
     */
    private String endpoint;

    /**
     * 送信元メールアドレス
     */
    private String fromAddress;
}
