package com.example.keirekipro.infrastructure.shared.aws.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import lombok.Getter;
import lombok.Setter;

/**
 * S3設定
 */
@Component
@Getter
@Setter
@ConfigurationProperties(prefix = "aws.s3")
public class AwsS3Properties {

    /**
     * リージョン
     */
    private String region;

    /**
     * エンドポイントURL（devのみ）
     */
    private String endpoint;

    /**
     * バケット名
     */
    private String bucketName;
}
