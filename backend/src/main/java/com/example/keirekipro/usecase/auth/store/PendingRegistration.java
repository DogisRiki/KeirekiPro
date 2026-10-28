package com.example.keirekipro.usecase.auth.store;

import java.time.Instant;
import java.util.UUID;

/**
 * 確認前の登録
 *
 * @param id 登録のID。確認を済ませたときに、同じIDでアカウントを作る
 * @param email メールアドレス
 * @param passwordHash ハッシュ化したパスワード
 * @param username ユーザー名
 * @param createdAt 登録を受け付けた日時
 */
public record PendingRegistration(
        UUID id,
        String email,
        String passwordHash,
        String username,
        Instant createdAt) {
}
