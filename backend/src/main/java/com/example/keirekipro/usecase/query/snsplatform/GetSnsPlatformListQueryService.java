package com.example.keirekipro.usecase.query.snsplatform;

import com.example.keirekipro.infrastructure.query.snsplatform.SnsPlatformQuery;
import com.example.keirekipro.usecase.query.snsplatform.dto.SnsPlatformListItemDto;

import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * SNSプラットフォーム一覧取得ユースケース
 */
@Service
@RequiredArgsConstructor
public class GetSnsPlatformListQueryService {

    private final SnsPlatformQuery snsPlatformQuery;

    /**
     * SNSプラットフォーム一覧取得ユースケースを実行する
     *
     * @return SNSプラットフォーム一覧ユースケースDTO
     */
    public SnsPlatformListItemDto execute() {
        return snsPlatformQuery.selectSnsPlatformListItem();
    }
}
