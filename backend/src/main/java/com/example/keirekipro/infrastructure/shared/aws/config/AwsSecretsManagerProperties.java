package com.example.keirekipro.infrastructure.shared.aws.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import lombok.Getter;
import lombok.Setter;

/**
 * Secrets Manager設定
 */
@Component
@Getter
@Setter
@ConfigurationProperties(prefix = "aws.secrets-manager")
public class AwsSecretsManagerProperties {

    /**
     * リージョン
     */
    private String region;

    /**
     * エンドポイントURL（devのみ）
     */
    private String endpoint;
}
