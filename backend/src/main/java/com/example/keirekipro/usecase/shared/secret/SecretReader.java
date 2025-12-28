package com.example.keirekipro.usecase.shared.secret;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * シークレット参照ポート
 */
public interface SecretReader {

    /**
     * JSON形式のシークレットを取得する
     *
     * @param secretName シークレット名
     * @return JSON
     */
    JsonNode readJson(String secretName);
}
