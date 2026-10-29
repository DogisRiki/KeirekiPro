package com.example.keirekipro.infrastructure.shared.aws.secrets;

import com.example.keirekipro.usecase.shared.secret.SecretReader;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest;

/**
 * Secrets Managerシークレットリーダー
 */
@Component
@RequiredArgsConstructor
public class SecretsManagerSecretReader implements SecretReader {

    /**
     * Secrets Managerクライアント
     */
    private final SecretsManagerClient secretsManagerClient;

    /**
     * JSONパーサー
     */
    private final JsonMapper jsonMapper;

    /**
     * JSON形式のシークレットを取得する
     *
     * @param secretName シークレット名
     * @return JSON
     */
    @Override
    public JsonNode readJson(String secretName) {

        GetSecretValueRequest request = GetSecretValueRequest.builder()
                .secretId(secretName)
                .build();

        String secretString = secretsManagerClient.getSecretValue(request).secretString();

        try {
            return jsonMapper.readTree(secretString);
        } catch (JacksonException e) {
            throw new RuntimeException("シークレットのパースに失敗しました。: " + secretName, e);
        }
    }
}
