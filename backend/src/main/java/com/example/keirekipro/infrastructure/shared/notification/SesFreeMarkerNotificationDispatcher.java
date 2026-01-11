package com.example.keirekipro.infrastructure.shared.notification;

import java.io.StringWriter;
import java.util.HashMap;
import java.util.Map;

import com.example.keirekipro.usecase.auth.notification.PasswordResetNotification;
import com.example.keirekipro.usecase.auth.notification.TwoFactorCodeNotification;
import com.example.keirekipro.usecase.shared.notification.Notification;
import com.example.keirekipro.usecase.shared.notification.NotificationDispatcher;
import com.example.keirekipro.usecase.user.notification.UserDeletedNotification;
import com.example.keirekipro.usecase.user.notification.UserRegisteredNotification;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

import freemarker.template.Configuration;
import freemarker.template.Template;
import software.amazon.awssdk.services.ses.SesClient;
import software.amazon.awssdk.services.ses.model.Body;
import software.amazon.awssdk.services.ses.model.Content;
import software.amazon.awssdk.services.ses.model.Destination;
import software.amazon.awssdk.services.ses.model.Message;
import software.amazon.awssdk.services.ses.model.SendEmailRequest;

/**
 * FreeMarker + SES 通知ディスパッチャー
 */
@Component
@RequiredArgsConstructor
public class SesFreeMarkerNotificationDispatcher implements NotificationDispatcher {

    /**
     * SESクライアント
     */
    private final SesClient sesClient;

    /**
     * FreeMarker設定
     */
    private final Configuration freeMarkerConfiguration;

    /**
     * 送信元メールアドレス
     */
    @Value("${aws.ses.from-address}")
    private String fromAddress;

    /**
     * 通知を送達する
     * 通知種別ごとのテンプレート選択・レンダリング・送達を本クラスに閉じ込める
     *
     * @param notification 通知
     */
    @Override
    public void dispatch(Notification notification) {

        if (notification instanceof UserRegisteredNotification n) {
            Map<String, Object> model = new HashMap<>();
            model.put("username", n.username());
            model.put("siteName", n.siteName());
            model.put("siteUrl", n.siteUrl());
            send(n.to(), "【" + n.siteName() + "】新規登録完了のお知らせ", "user-registered.ftl", model);
            return;
        }

        if (notification instanceof UserDeletedNotification n) {
            Map<String, Object> model = new HashMap<>();
            model.put("username", n.username());
            model.put("siteName", n.siteName());
            model.put("siteUrl", n.siteUrl());
            send(n.to(), "【" + n.siteName() + "】退会手続き完了のお知らせ", "user-deleted.ftl", model);
            return;
        }

        if (notification instanceof PasswordResetNotification n) {
            Map<String, Object> model = new HashMap<>();
            model.put("resetLink", n.resetLink());
            model.put("siteName", n.siteName());
            model.put("siteUrl", n.siteUrl());
            send(n.to(), "【" + n.siteName() + "】パスワードリセットのご案内", "password-reset.ftl", model);
            return;
        }

        if (notification instanceof TwoFactorCodeNotification n) {
            Map<String, Object> model = new HashMap<>();
            model.put("code", n.code());
            model.put("siteName", n.siteName());
            model.put("siteUrl", n.siteUrl());
            send(n.to(), "【" + n.siteName() + "】2段階認証コードのお知らせ", "two-factor-auth.ftl", model);
        }
    }

    /**
     * テンプレートをレンダリングしてSESで送信する
     *
     * @param to           宛先
     * @param subject      件名
     * @param templateName テンプレート名
     * @param dataModel    テンプレートデータ
     */
    private void send(String to, String subject, String templateName, Map<String, Object> dataModel) {

        String body = render(templateName, dataModel);

        Destination destination = Destination.builder()
                .toAddresses(to)
                .build();

        Message message = Message.builder()
                .subject(Content.builder().data(subject).build())
                .body(Body.builder()
                        .text(Content.builder().data(body).build())
                        .build())
                .build();

        SendEmailRequest request = SendEmailRequest.builder()
                .destination(destination)
                .message(message)
                .source(fromAddress)
                .build();

        sesClient.sendEmail(request);
    }

    /**
     * FreeMarkerテンプレートをレンダリングする
     *
     * @param templateName テンプレート名
     * @param dataModel    テンプレートデータ
     * @return 本文
     */
    private String render(String templateName, Map<String, Object> dataModel) {
        try {
            Template template = freeMarkerConfiguration.getTemplate(templateName);
            StringWriter writer = new StringWriter();
            template.process(dataModel, writer);
            return writer.toString();
        } catch (Exception e) {
            throw new RuntimeException("FreeMarkerテンプレート処理に失敗: " + templateName, e);
        }
    }
}
