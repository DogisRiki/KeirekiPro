package com.example.keirekipro.infrastructure.shared.aws.secrets;

import java.io.IOException;

import com.example.keirekipro.usecase.shared.secret.SecretReader;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

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
    private final ObjectMapper objectMapper;

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
            return objectMapper.readTree(secretString);
        } catch (IOException e) {
            throw new RuntimeException("シークレットのパースに失敗しました。: " + secretName, e);
        }
    }
}
