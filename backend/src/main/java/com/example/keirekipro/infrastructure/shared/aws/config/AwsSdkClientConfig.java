package com.example.keirekipro.infrastructure.shared.aws.config;

import java.net.URI;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;
import software.amazon.awssdk.services.ses.SesClient;

/**
 * AWS SDKクライアント設定
 */
public class AwsSdkClientConfig {

    /**
     * dev環境用（LocalStack）
     */
    @Configuration
    @Profile("dev")
    static class Dev {

        /**
         * S3Clientを生成する
         *
         * @param props S3設定
         * @return S3Client
         */
        @Bean
        public S3Client s3Client(AwsS3Properties props) {
            return S3Client.builder()
                    .region(Region.of(props.getRegion()))
                    .credentialsProvider(DefaultCredentialsProvider.create())
                    .endpointOverride(URI.create(props.getEndpoint()))
                    .serviceConfiguration(S3Configuration.builder().pathStyleAccessEnabled(true).build())
                    .build();
        }

        /**
         * S3Presignerを生成する
         *
         * @param props S3設定
         * @return S3Presigner
         */
        @Bean
        public S3Presigner s3Presigner(AwsS3Properties props) {
            return S3Presigner.builder()
                    .region(Region.of(props.getRegion()))
                    .credentialsProvider(DefaultCredentialsProvider.create())
                    .endpointOverride(URI.create(props.getEndpoint()))
                    .serviceConfiguration(S3Configuration.builder().pathStyleAccessEnabled(true).build())
                    .build();
        }

        /**
         * SesClientを生成する
         *
         * @param props SES設定
         * @return SesClient
         */
        @Bean
        public SesClient sesClient(AwsSesProperties props) {
            return SesClient.builder()
                    .region(Region.of(props.getRegion()))
                    .credentialsProvider(DefaultCredentialsProvider.create())
                    .endpointOverride(URI.create(props.getEndpoint()))
                    .build();
        }

        /**
         * SecretsManagerClientを生成する
         *
         * @param props Secrets Manager設定
         * @return SecretsManagerClient
         */
        @Bean
        public SecretsManagerClient secretsManagerClient(AwsSecretsManagerProperties props) {
            return SecretsManagerClient.builder()
                    .region(Region.of(props.getRegion()))
                    .credentialsProvider(DefaultCredentialsProvider.create())
                    .endpointOverride(URI.create(props.getEndpoint()))
                    .build();
        }
    }

    /**
     * 本番環境用
     */
    @Configuration
    @Profile("!dev")
    static class Prod {

        /**
         * S3Clientを生成する
         *
         * @param props S3設定
         * @return S3Client
         */
        @Bean
        public S3Client s3Client(AwsS3Properties props) {
            return S3Client.builder()
                    .region(Region.of(props.getRegion()))
                    .credentialsProvider(DefaultCredentialsProvider.create())
                    .build();
        }

        /**
         * S3Presignerを生成する
         *
         * @param props S3設定
         * @return S3Presigner
         */
        @Bean
        public S3Presigner s3Presigner(AwsS3Properties props) {
            return S3Presigner.builder()
                    .region(Region.of(props.getRegion()))
                    .credentialsProvider(DefaultCredentialsProvider.create())
                    .build();
        }

        /**
         * SesClientを生成する
         *
         * @param props SES設定
         * @return SesClient
         */
        @Bean
        public SesClient sesClient(AwsSesProperties props) {
            return SesClient.builder()
                    .region(Region.of(props.getRegion()))
                    .credentialsProvider(DefaultCredentialsProvider.create())
                    .build();
        }

        /**
         * SecretsManagerClientを生成する
         *
         * @param props Secrets Manager設定
         * @return SecretsManagerClient
         */
        @Bean
        public SecretsManagerClient secretsManagerClient(AwsSecretsManagerProperties props) {
            return SecretsManagerClient.builder()
                    .region(Region.of(props.getRegion()))
                    .credentialsProvider(DefaultCredentialsProvider.create())
                    .build();
        }
    }
}
