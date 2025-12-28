package com.example.keirekipro.unit.infrastructure.shared.aws.secrets;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.example.keirekipro.infrastructure.shared.aws.secrets.SecretsManagerSecretReader;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueResponse;

@ExtendWith(MockitoExtension.class)
class SecretsManagerSecretReaderTest {

    @Mock
    private SecretsManagerClient secretsManagerClient;

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    @DisplayName("指定したシークレット文字列からJSONデータを取得できる")
    void test1() {
        GetSecretValueResponse response = GetSecretValueResponse.builder()
                .secretString("{\"key\":\"value\"}")
                .build();
        when(secretsManagerClient.getSecretValue(any(GetSecretValueRequest.class))).thenReturn(response);

        SecretsManagerSecretReader reader = new SecretsManagerSecretReader(secretsManagerClient, objectMapper);

        JsonNode result = reader.readJson("dummySecret");

        assertThat(result.get("key").asText()).isEqualTo("value");

        ArgumentCaptor<GetSecretValueRequest> captor = ArgumentCaptor.forClass(GetSecretValueRequest.class);
        verify(secretsManagerClient).getSecretValue(captor.capture());
        assertThat(captor.getValue().secretId()).isEqualTo("dummySecret");
    }

    @Test
    @DisplayName("取得したJSONデータが無効なデータだった場合、RuntimeExceptionがスローされる")
    void test2() {
        GetSecretValueResponse response = GetSecretValueResponse.builder()
                .secretString("invalid json")
                .build();
        when(secretsManagerClient.getSecretValue(any(GetSecretValueRequest.class))).thenReturn(response);

        SecretsManagerSecretReader reader = new SecretsManagerSecretReader(secretsManagerClient, objectMapper);

        assertThatThrownBy(() -> reader.readJson("dummySecret"))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("dummySecret");
    }
}
