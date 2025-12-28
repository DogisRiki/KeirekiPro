package com.example.keirekipro.unit.infrastructure.shared.aws.s3;

import static org.assertj.core.api.Assertions.assertThat;

import com.example.keirekipro.infrastructure.shared.aws.config.AwsS3Properties;
import com.example.keirekipro.infrastructure.shared.aws.s3.LocalstackPresignedUrlTransformer;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class LocalstackPresignedUrlTransformerTest {

    @Test
    @DisplayName("LocalStackの署名付きURLのホストをlocalhostに補正できる")
    void test1() {
        AwsS3Properties props = new AwsS3Properties();
        props.setEndpoint("http://localstack:4566");

        LocalstackPresignedUrlTransformer transformer = new LocalstackPresignedUrlTransformer(props);

        String input = "http://localstack:4566/test-bucket/path/to/file.png?X-Amz-Signature=xxx";
        String output = transformer.transform(input);

        assertThat(output).startsWith("http://localhost:4566/");
        assertThat(output).contains("X-Amz-Signature=xxx");
    }
}
