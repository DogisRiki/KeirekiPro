package com.example.keirekipro.usecase.auth;

import java.time.Duration;
import java.util.UUID;

import com.example.keirekipro.shared.config.AppProperties;
import com.example.keirekipro.shared.utils.SecurityUtil;
import com.example.keirekipro.usecase.auth.notification.TwoFactorCodeNotification;
import com.example.keirekipro.usecase.auth.store.TwoFactorAuthCodeStore;
import com.example.keirekipro.usecase.shared.notification.NotificationDispatcher;

import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * 2段階認証コード発行ユースケース
 */
@Service
@RequiredArgsConstructor
public class TwoFactorAuthIssueUseCase {

    private final TwoFactorAuthCodeStore twoFactorAuthCodeStore;

    private final NotificationDispatcher notificationDispatcher;

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

        // 保存
        twoFactorAuthCodeStore.store(userId, code, Duration.ofMinutes(10));

        // 通知送達
        notificationDispatcher.dispatch(new TwoFactorCodeNotification(
                email,
                code,
                properties.getSiteName(),
                properties.getSiteUrl()));
    }
}
