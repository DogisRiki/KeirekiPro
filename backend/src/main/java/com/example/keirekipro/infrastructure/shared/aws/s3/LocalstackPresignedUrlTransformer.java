package com.example.keirekipro.infrastructure.shared.aws.s3;

import java.net.URI;

import com.example.keirekipro.infrastructure.shared.aws.config.AwsS3Properties;

import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * LocalStack用 署名付きURL変換
 */
@Component
@Profile("dev")
@RequiredArgsConstructor
public class LocalstackPresignedUrlTransformer implements PresignedUrlTransformer {

    /**
     * S3設定
     */
    private final AwsS3Properties properties;

    /**
     * LocalStackの署名付きURLのホストをlocalhostに補正する
     *
     * @param url 元URL
     * @return 変換後URL
     */
    @Override
    public String transform(String url) {
        String originalHost = URI.create(properties.getEndpoint()).getHost();
        return url.replace(originalHost, "localhost");
    }
}
