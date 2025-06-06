package com.example.keirekipro.usecase.auth;

import java.time.Duration;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import com.example.keirekipro.infrastructure.shared.aws.AwsSesClient;
import com.example.keirekipro.infrastructure.shared.mail.FreeMarkerMailTemplate;
import com.example.keirekipro.infrastructure.shared.redis.RedisClient;
import com.example.keirekipro.shared.config.AppProperties;
import com.example.keirekipro.shared.utils.SecurityUtil;

import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * 2段階認証コード発行ユースケース
 */
@Service
@RequiredArgsConstructor
public class TwoFactorAuthIssueUseCase {

    private final RedisClient redisClient;

    private final AwsSesClient awsSesClient;

    private final FreeMarkerMailTemplate freeMarkerMailTemplate;

    private final SecurityUtil securityUtil;

    private final AppProperties properties;

    /**
     * 2段階認証コード発行ユースケースを実行する
     *
     * @param userId ユーザーID
     * @param email  送信先メールアドレス
     */
    public void execute(UUID userId, String email) {

        // 6桁のコードを生成
        String code = securityUtil.generateRandomNumber(6);

        // Redisに保存
        String key = "2fa:" + userId;
        redisClient.setValue(key, code, Duration.ofMinutes(10));

        // メール本文を作成
        Map<String, Object> dataModel = new HashMap<>();
        dataModel.put("code", code);
        dataModel.put("siteName", properties.getSiteName());
        dataModel.put("siteUrl", properties.getSiteUrl());
        String body = freeMarkerMailTemplate.create("two-factor-auth.ftl", dataModel);

        // メール送信
        awsSesClient.sendMail(email, "【" + properties.getSiteName() + "】2段階認証コードのお知らせ", body);
    }
}
