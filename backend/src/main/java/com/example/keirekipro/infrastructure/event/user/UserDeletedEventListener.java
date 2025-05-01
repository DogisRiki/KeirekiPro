package com.example.keirekipro.infrastructure.event.user;

import java.util.HashMap;
import java.util.Map;

import com.example.keirekipro.domain.event.user.UserDeletedEvent;
import com.example.keirekipro.infrastructure.shared.aws.AwsSesClient;
import com.example.keirekipro.infrastructure.shared.mail.FreeMarkerMailTemplate;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * ユーザー削除イベントリスナー
 */
@Component
@RequiredArgsConstructor
public class UserDeletedEventListener {

    private final AwsSesClient awsSesClient;

    private final FreeMarkerMailTemplate freeMarkerMailTemplate;

    @Value("${spring.application.name}")
    private String applicationName;

    /**
     * イベントリスナー実行ハンドル
     *
     * @param event ユーザー削除イベント
     */
    @EventListener
    public void handle(UserDeletedEvent event) {

        // メール本文を作成
        Map<String, Object> dataModel = new HashMap<>();
        dataModel.put("username", event.getUsername());
        String body = freeMarkerMailTemplate.create("user-deleted.ftl", dataModel);

        // メール送信
        awsSesClient.sendMail(event.getEmail(), "【" + applicationName + "】退会手続きが完了しました", body);
    }
}
