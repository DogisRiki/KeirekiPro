package com.example.keirekipro.infrastructure.shared.aws.s3;

/**
 * 署名付きURL変換戦略
 */
public interface PresignedUrlTransformer {

    /**
     * URLを変換する
     *
     * @param url 元URL
     * @return 変換後URL
     */
    String transform(String url);
}
