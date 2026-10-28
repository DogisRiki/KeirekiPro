package com.example.keirekipro.usecase.auth.store;

import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

/**
 * 最新の確認のリンクのIDの保管ポート
 * 対象（確認前の登録かアカウント）ごとに、最後に送ったリンクのjtiを1つだけ持つ
 */
public interface EmailVerificationCurrentTokenStore {

    /**
     * 最新のjtiを置き換える
     *
     * @param subjectId 対象のID
     * @param jti リンクのID
     * @param ttl そのリンクの期限までの時間
     */
    void put(UUID subjectId, String jti, Duration ttl);

    /**
     * 最新のjtiを読む
     *
     * @param subjectId 対象のID
     * @return jti（存在しない場合はempty）
     */
    Optional<String> find(UUID subjectId);

    /**
     * 置いてある値がjtiと同じときだけ消す
     *
     * @param subjectId 対象のID
     * @param jti リンクのID
     * @return 消せた場合はtrue
     */
    boolean consume(UUID subjectId, String jti);

    /**
     * 最新のjtiを消す
     *
     * @param subjectId 対象のID
     */
    void clear(UUID subjectId);
}
