package com.example.keirekipro.infrastructure.shared.aws.s3;

import java.net.URI;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

/**
 * LocalStack用 署名付きURL変換
 */
@Component
@Profile("dev")
public class LocalstackPresignedUrlTransformer implements PresignedUrlTransformer {

    /**
     * エンドポイント
     */
    @Value("${spring.cloud.aws.endpoint}")
    private String endpoint;

    /**
     * LocalStackの署名付きURLのホストをlocalhostに補正する
     *
     * @param url 元URL
     * @return 変換後URL
     */
    @Override
    public String transform(String url) {
        String originalHost = URI.create(endpoint).getHost();
        return url.replace(originalHost, "localhost");
    }
}
