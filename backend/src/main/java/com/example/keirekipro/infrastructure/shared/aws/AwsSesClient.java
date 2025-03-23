package com.example.keirekipro.infrastructure.shared.aws;

import java.net.URI;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import lombok.Getter;
import lombok.Setter;

import jakarta.annotation.PostConstruct;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.ses.SesClient;
import software.amazon.awssdk.services.ses.SesClientBuilder;
import software.amazon.awssdk.services.ses.model.Body;
import software.amazon.awssdk.services.ses.model.Content;
import software.amazon.awssdk.services.ses.model.Destination;
import software.amazon.awssdk.services.ses.model.Message;
import software.amazon.awssdk.services.ses.model.SendEmailRequest;

/**
 * AWS SESでメール送信を行うクラス
 */
@Getter
@Setter
@Component
@ConfigurationProperties(prefix = "aws.ses")
public class AwsSesClient {

    /**
     * リージョン
     */
    private String region;

    /**
     * AWS SESへのエンドポイントURL(localStackの場合のみ必要)
     * localStackを使用する開発環境の場合は必要。
     * AWS本番環境ではSDKが自動的にAWSの正規エンドポイントを判断するため不要。
     */
    private String endpoint;

    /**
     * AWS SESで検証済みの送信元メールアドレス
     */
    private String fromAddress;

    /**
     * SESクライアント
     */
    private SesClient sesClient;

    /**
     * Bean初期化時にSesClientを初期化する
     */
    @PostConstruct
    public void init() {
        // ビルダー初期化(Region, CredentialsProviderをセット)
        SesClientBuilder builder = SesClient.builder()
                .region(Region.of(this.region))
                .credentialsProvider(DefaultCredentialsProvider.create());
        // エンドポイントが設定されていれば上書き(localStackの場合)
        if (endpoint != null && !endpoint.isEmpty()) {
            builder.endpointOverride(URI.create(endpoint));
        }
        // クライアント生成
        this.sesClient = builder.build();
    }

    /**
     * すでに完成しているメール本文を受け取り、SESへ送信する
     *
     * @param to      宛先メールアドレス
     * @param subject メール件名
     * @param body    プレーンテキストの本文
     */
    public void sendMail(String to, String subject, String body) {

        // Destination: 宛先
        Destination destination = Destination.builder()
                .toAddresses(to)
                .build();

        // Message: 件名＋本文
        Message message = Message.builder()
                .subject(Content.builder().data(subject).build())
                .body(Body.builder()
                        .text(Content.builder().data(body).build())
                        .build())
                .build();

        // SendEmailRequest: リクエスト作成
        SendEmailRequest request = SendEmailRequest.builder()
                .destination(destination)
                .message(message)
                .source(this.fromAddress)
                .build();

        // SESへ送信
        sesClient.sendEmail(request);
    }
}
