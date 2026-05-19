package com.example.keirekipro.infrastructure.store.auth;

import java.time.LocalDateTime;
import java.util.Optional;
import java.util.UUID;

import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

/**
 * ユーザートークンバージョンマッパー
 */
@Mapper
public interface UserTokenVersionMapper {

    /**
     * ユーザーIDからトークンバージョンを取得する
     *
     * @param userId ユーザーID
     * @return トークンバージョン
     */
    Optional<Long> selectByUserId(@Param("userId") UUID userId);

    /**
     * トークンバージョンを新規登録する
     *
     * @param userId ユーザーID
     * @param updatedAt 更新日時
     */
    void insert(@Param("userId") UUID userId, @Param("updatedAt") LocalDateTime updatedAt);

    /**
     * トークンバージョンをインクリメントする
     *
     * @param userId ユーザーID
     * @param updatedAt 更新日時
     */
    void incrementByUserId(@Param("userId") UUID userId, @Param("updatedAt") LocalDateTime updatedAt);
}
