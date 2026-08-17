package com.example.keirekipro;

import com.example.keirekipro.config.PostgresTestContainerConfig;
import com.example.keirekipro.config.RedisTestContainerConfig;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;
import software.amazon.awssdk.services.ses.SesClient;

/**
 * アプリケーションコンテキストが起動することを検証するテスト。
 *
 * Bean定義や設定の誤りは、他のテストが層ごとに切り出したコンテキストを使うため
 * 検知されない。全体を組み上げるのはこのテストだけであり、無効化すると
 * 起動できない状態でマージされてもデプロイまで気づけない。
 *
 * DBとRedisはTestcontainersで実物を立てる。AWSのクライアントはモックにする。
 * test プロファイルが spring.cloud.aws.* を無効化しており自動構成が行われないため、
 * 依存する側のBean生成が失敗する。ここで検証したいのは配線であって
 * AWSの動作ではないため、実物やLocalStackは使わない。
 */
@SpringBootTest
@ActiveProfiles("test")
@Import({ PostgresTestContainerConfig.class, RedisTestContainerConfig.class })
class KeirekiProApplicationTests {

    @MockitoBean
    private SecretsManagerClient secretsManagerClient;

    @MockitoBean
    private S3Client s3Client;

    @MockitoBean
    private S3Presigner s3Presigner;

    @MockitoBean
    private SesClient sesClient;

    @Autowired
    private ApplicationContext applicationContext;

    @Test
    void コンテキストが起動し主要なBeanが解決できる() {
        assertThat(applicationContext).isNotNull();
        assertThat(applicationContext.getBeanDefinitionCount()).isPositive();
    }

}
