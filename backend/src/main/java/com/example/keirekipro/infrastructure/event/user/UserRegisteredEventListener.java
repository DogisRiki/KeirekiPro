package com.example.keirekipro.infrastructure.event.user;

import java.util.HashMap;
import java.util.Map;

import com.example.keirekipro.domain.event.user.UserRegisteredEvent;
import com.example.keirekipro.infrastructure.shared.aws.AwsSesClient;
import com.example.keirekipro.infrastructure.shared.mail.FreeMarkerMailTemplate;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * ユーザー登録イベントリスナー
 */
@Component
@RequiredArgsConstructor
public class UserRegisteredEventListener {

    private final AwsSesClient awsSesClient;

    private final FreeMarkerMailTemplate freeMarkerMailTemplate;

    @Value("${spring.application.name}")
    private String applicationName;

    /**
     * イベントリスナー実行ハンドル
     *
     * @param event ユーザー登録イベント
     */
    @EventListener
    public void handle(UserRegisteredEvent event) {

        // メール本文を作成
        Map<String, Object> dataModel = new HashMap<>();
        dataModel.put("username", event.getUsername());
        String body = freeMarkerMailTemplate.create("user-registered.ftl", dataModel);

        // メール送信
        awsSesClient.sendMail(event.getEmail(), "【" + applicationName + "】新規登録完了のお知らせ", body);
    }
}
