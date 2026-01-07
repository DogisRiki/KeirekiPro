package com.example.keirekipro.presentation.snsplatform.dto;

import java.util.List;

import com.example.keirekipro.usecase.query.snsplatform.dto.SnsPlatformListQueryDto;

import lombok.AccessLevel;
import lombok.EqualsAndHashCode;
import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * SNSプラットフォーム一覧レスポンス
 */
@Getter
@EqualsAndHashCode
@RequiredArgsConstructor(access = AccessLevel.PRIVATE)
public class SnsPlatformListResponse {

    private final List<String> names;

    /**
     * クエリDTOからレスポンスDTOへ変換する
     *
     * @param dto クエリDTO
     * @return レスポンスDTO
     */
    public static SnsPlatformListResponse convertFrom(SnsPlatformListQueryDto dto) {
        return new SnsPlatformListResponse(dto.getNames());
    }
}
