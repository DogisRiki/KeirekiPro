package com.example.keirekipro.unit.infrastructure.shared.aws;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;

import com.example.keirekipro.config.YamlPropertySourceFactory;
import com.example.keirekipro.infrastructure.shared.aws.AwsSesClient;

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

import software.amazon.awssdk.services.ses.SesClient;
import software.amazon.awssdk.services.ses.model.SendEmailRequest;

@SpringJUnitConfig(AwsSesClientTest.TestConfig.class)
@TestPropertySource(locations = "classpath:application-test.yaml", factory = YamlPropertySourceFactory.class)
@ActiveProfiles("test")
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
@ExtendWith(MockitoExtension.class)
class AwsSesClientTest {

    private final AwsSesClient awsSesClient;

    @Mock
    private SesClient sesClient;

    @Test
    @DisplayName("@PostConstructによりAwsSesClientが正しくインスタンス化される")
    void test1() {
        // プロパティがバインドされている
        assertThat(awsSesClient.getRegion()).isEqualTo("ap-northeast-1");
        assertThat(awsSesClient.getEndpoint()).isEqualTo("http://localhost:4566");

        // SesClientのインスタンスが存在し、正しい
        assertThat(awsSesClient.getSesClient())
                .isNotNull()
                .isInstanceOf(SesClient.class);
    }

    @Test
    @DisplayName("メールをSESに送信できる")
    void test2() {
        // テスト対象のAwsSesClientの内部依存をモックに上書き
        awsSesClient.setSesClient(sesClient);

        // テストデータ
        String to = "test@example.com";
        String subject = "テスト件名";
        String body = "テスト本文";

        // 例外が発生せずに実行できることを確認
        assertThatCode(() -> {
            awsSesClient.sendMail(to, subject, body);
        }).doesNotThrowAnyException();

        // SendEmailメソッドが呼び出されたことを検証
        verify(sesClient).sendEmail(any(SendEmailRequest.class));
    }

    @TestConfiguration
    @EnableConfigurationProperties(AwsSesClient.class)
    static class TestConfig {
    }
}
