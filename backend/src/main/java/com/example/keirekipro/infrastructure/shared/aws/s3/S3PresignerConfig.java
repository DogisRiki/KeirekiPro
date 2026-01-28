package com.example.keirekipro.infrastructure.shared.aws.s3;

import java.net.URI;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

/**
 * S3Presigner設定
 */
@Configuration
public class S3PresignerConfig {

    @Bean
    @Profile("prod")
    S3Presigner prodS3Presigner(
            @Value("${spring.cloud.aws.region.static}") String region) {
        return S3Presigner.builder()
                .region(Region.of(region))
                .build();
    }

    @Bean
    @Profile("dev")
    S3Presigner devS3Presigner(
            @Value("${spring.cloud.aws.region.static}") String region,
            @Value("${spring.cloud.aws.endpoint}") String endpoint) {
        return S3Presigner.builder()
                .region(Region.of(region))
                .endpointOverride(URI.create(endpoint))
                .serviceConfiguration(
                        S3Configuration.builder()
                                .pathStyleAccessEnabled(true)
                                .build())
                .build();
    }
}
