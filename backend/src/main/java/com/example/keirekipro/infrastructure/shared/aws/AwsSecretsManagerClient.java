package com.example.keirekipro.infrastructure.shared.aws;

import java.io.IOException;
import java.net.URI;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import lombok.Getter;
import lombok.Setter;

import jakarta.annotation.PostConstruct;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClientBuilder;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest;

/**
 * AWS Secrets Managerからシステムで利用する秘匿情報を提供する汎用クラス
 */
@Component
@Getter
@Setter
@ConfigurationProperties(prefix = "aws.secrets-manager")
public class AwsSecretsManagerClient {

    /**
     * リージョン
     */
    private String region;

    /**
     * AWS Secrets ManagerへのエンドポイントURL(localStackの場合のみ必要)
     * localStackを使用する開発環境の場合は必要。
     * AWS本番環境ではSDKが自動的にAWSの正規エンドポイントを判断するため不要。
     */
    private String endpoint;

    /**
     * SecretsManagerクライアント
     */
    private SecretsManagerClient secretsManagerClient;

    private final ObjectMapper objectMapper = new ObjectMapper();

    /**
     * Bean初期化時にSecretsManagerClientを初期化する
     */
    @PostConstruct
    public void init() {
        // ビルダー初期化(Region, CredentialsProviderをセット)
        SecretsManagerClientBuilder builder = SecretsManagerClient.builder().region(Region.of(this.region))
                .credentialsProvider(DefaultCredentialsProvider.create());
        // エンドポイントが設定されていれば上書き(localStackの場合)
        if (this.endpoint != null && !this.endpoint.isEmpty()) {
            builder.endpointOverride(URI.create(this.endpoint));
        }
        // クライアント生成
        this.secretsManagerClient = builder.build();
    }

    /**
     * 指定したシークレット名からJSONデータを取得して返す
     *
     * @param secretName 取得したいシークレット名
     * @return シークレットをJSONパースした結果
     */
    public JsonNode getSecretJson(String secretName) {
        // Secrets Managerへのリクエストを作成
        GetSecretValueRequest request = GetSecretValueRequest.builder().secretId(secretName).build();
        // Secrets ManagerからシークレットをJSON文字列として取得
        String secretString = secretsManagerClient.getSecretValue(request).secretString();
        // JSONにパース
        try {
            return objectMapper.readTree(secretString);
        } catch (IOException e) {
            throw new RuntimeException("シークレットのパースに失敗しました。: " + secretName, e);
        }
    }
}
