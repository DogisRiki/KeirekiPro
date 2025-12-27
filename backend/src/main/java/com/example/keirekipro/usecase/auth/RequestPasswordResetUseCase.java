package com.example.keirekipro.usecase.auth;

import java.time.Duration;
import java.util.HashMap;
import java.util.Map;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.infrastructure.shared.aws.AwsSesClient;
import com.example.keirekipro.infrastructure.shared.mail.FreeMarkerMailTemplate;
import com.example.keirekipro.infrastructure.shared.redis.RedisClient;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.shared.utils.SecurityUtil;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * パスワードリセット要求ユースケース
 */
@Service
@RequiredArgsConstructor
public class RequestPasswordResetUseCase {

    private final UserRepository userRepository;

    private final RedisClient redisClient;

    private final AwsSesClient awsSesClient;

    private final FreeMarkerMailTemplate freeMarkerMailTemplate;

    private final SecurityUtil securityUtil;

    @Value("${frontend-base-url}")
    private String frontendBaseUrl;

    @Value("${spring.application.name}")
    private String applicationName;

    /**
     * パスワードリセット要求ユースケースを実行する
     *
     * @param to 宛先メールアドレス
     */
    public void execute(String to) {

        Email email = Email.create(new ErrorCollector(), to);

        // 該当ユーザーを検索（存在しない場合は何もせず終了）
        userRepository.findByEmail(email.getValue())
                .ifPresent(user -> {
                    // トークンを生成
                    String token = securityUtil.generateRandomToken();

                    // トークンを保存
                    String key = "password-reset:" + token;
                    redisClient.setValue(key, user.getId().toString(), Duration.ofMinutes(10));

                    // リセットリンクを生成
                    String resetLink = frontendBaseUrl + "/password/reset/" + token;

                    // メール本文を作成
                    Map<String, Object> dataModel = new HashMap<>();
                    dataModel.put("resetLink", resetLink);
                    dataModel.put("siteName", applicationName);
                    dataModel.put("siteUrl", frontendBaseUrl);
                    String body = freeMarkerMailTemplate.create("password-reset.ftl", dataModel);

                    // メール送信
                    awsSesClient.sendMail(user.getEmail().getValue(), "【" + applicationName + "】パスワードリセットのご案内", body);
                });
    }
}
