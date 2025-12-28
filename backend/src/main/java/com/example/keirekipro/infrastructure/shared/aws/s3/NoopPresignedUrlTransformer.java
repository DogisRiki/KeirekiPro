package com.example.keirekipro.infrastructure.shared.aws.s3;

import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

/**
 * 署名付きURL変換なし（本番用）
 */
@Component
@Profile("!dev")
public class NoopPresignedUrlTransformer implements PresignedUrlTransformer {

    /**
     * 変換を行わず、そのまま返す
     *
     * @param url 元URL
     * @return 元URL
     */
    @Override
    public String transform(String url) {
        return url;
    }
}
