package com.example.keirekipro.usecase.query.snsplatform;

import com.example.keirekipro.usecase.query.snsplatform.dto.SnsPlatformListQueryDto;

/**
 * SNSプラットフォーム一覧取得クエリインターフェース
 */
public interface SnsPlatformListQuery {

    /**
     * SNSプラットフォーム一覧を取得する
     *
     * @return SNSプラットフォーム一覧クエリDTO
     */
    SnsPlatformListQueryDto findAll();
}
