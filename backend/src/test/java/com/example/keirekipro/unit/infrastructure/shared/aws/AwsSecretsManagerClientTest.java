package com.example.keirekipro.unit.infrastructure.shared.aws;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import com.example.keirekipro.config.YamlPropertySourceFactory;
import com.example.keirekipro.infrastructure.shared.aws.AwsSecretsManagerClient;
import com.fasterxml.jackson.databind.JsonNode;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.junit.jupiter.SpringJUnitConfig;

import lombok.RequiredArgsConstructor;

import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueResponse;

@SpringJUnitConfig(AwsSecretsManagerClientTest.TestConfig.class)
@TestPropertySource(locations = "classpath:application-test.yaml", factory = YamlPropertySourceFactory.class)
@ActiveProfiles("test")
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
@ExtendWith(MockitoExtension.class)
class AwsSecretsManagerClientTest {

    private final AwsSecretsManagerClient awsSecretsManagerClient;

    @Mock
    private SecretsManagerClient secretsManagerClient;

    @Test
    @DisplayName("@PostConstructによりAwsSecretsManagerClientが正しくインスタンス化される")
    void test1() {
        // プロパティがバインドされている
        assertThat(awsSecretsManagerClient.getRegion()).isEqualTo("ap-northeast-1");
        assertThat(awsSecretsManagerClient.getEndpoint()).isEqualTo("http://localhost:4566");
        // SecretsManagerClientのインスタンスが存在し、正しい
        assertThat(awsSecretsManagerClient.getSecretsManagerClient())
                .isNotNull()
                .isInstanceOf(SecretsManagerClient.class);
    }

    @Test
    @DisplayName("指定したシークレット文字列からJSONデータを取得できる")
    void test2() {
        GetSecretValueResponse response = GetSecretValueResponse.builder()
                .secretString("{\"key\":\"value\"}")
                .build();
        when(secretsManagerClient.getSecretValue(any(GetSecretValueRequest.class))).thenReturn(response);

        // テスト対象のAwsSecretsManagerClientの内部依存をモックに上書き
        awsSecretsManagerClient.setSecretsManagerClient(secretsManagerClient);

        JsonNode result = awsSecretsManagerClient.getSecretJson("dummySecret");
        assertThat(result.get("key").asText()).isEqualTo("value");
    }

    @Test
    @DisplayName("取得したJSONデータが無効なデータだった場合、例外をスローする")
    public void test3() {
        GetSecretValueResponse response = GetSecretValueResponse.builder()
                .secretString("invalid json")
                .build();
        when(secretsManagerClient.getSecretValue(any(GetSecretValueRequest.class))).thenReturn(response);

        // テスト対象のAwsSecretsManagerClientの内部依存をモックに上書き
        awsSecretsManagerClient.setSecretsManagerClient(secretsManagerClient);

        assertThatThrownBy(() -> awsSecretsManagerClient.getSecretJson("dummySecret"))
                .isInstanceOf(RuntimeException.class);
    }

    @TestConfiguration
    @EnableConfigurationProperties(AwsSecretsManagerClient.class)
    static class TestConfig {
    }
}
