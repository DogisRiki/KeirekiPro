package com.example.keirekipro.domain.repository.user;

import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.User;

/**
 * ユーザーリポジトリ
 */
public interface UserRepository {

    /**
     * ユーザーを取得する
     *
     * @param userId ユーザーID
     * @return ユーザーエンティティ
     */
    Optional<User> findById(UUID userId);

    /**
     * ユーザーを取得する
     *
     * @param email メールアドレス
     * @return ユーザーエンティティ
     */
    Optional<User> findByEmail(String email);

    /**
     * ユーザーを保存する（新規作成または更新）
     *
     * @param user ユーザーエンティティ
     */
    void save(User user);

    /**
     * ユーザーを削除する
     *
     * @param userId ユーザーID
     */
    void delete(UUID userId);
}
