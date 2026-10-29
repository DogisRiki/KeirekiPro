package com.example.keirekipro.usecase.auth.store;

import java.time.Duration;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * 確認前の登録の保管ポート
 */
public interface PendingRegistrationStore {

    /**
     * 登録を置く。同じIDの登録があれば上書きする
     *
     * @param registration 確認前の登録
     * @param ttl 有効期限
     */
    void save(PendingRegistration registration, Duration ttl);

    /**
     * IDで登録を読む
     *
     * @param id 登録のID
     * @return 登録（存在しない場合はempty）
     */
    Optional<PendingRegistration> findById(UUID id);

    /**
     * メールアドレスの登録を、作った日時の新しい順に返す
     *
     * @param email メールアドレス
     * @param limit 返す件数の上限
     * @return 登録の一覧
     */
    List<PendingRegistration> findByEmail(String email, int limit);

    /**
     * 登録の有効期限を延ばす
     *
     * @param id 登録のID
     * @param ttl 有効期限
     */
    void extend(UUID id, Duration ttl);

    /**
     * 登録と、メールアドレスごとの登録のIDの集合の中のその登録のIDを消す
     *
     * @param registration 確認前の登録
     */
    void delete(PendingRegistration registration);
}
