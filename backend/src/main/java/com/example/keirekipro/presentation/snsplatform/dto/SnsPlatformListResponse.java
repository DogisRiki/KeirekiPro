package com.example.keirekipro.presentation.snsplatform.dto;

import java.util.List;

import com.example.keirekipro.usecase.query.snsplatform.dto.SnsPlatformListItemDto;

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
     * ユースケースDTOからレスポンスDTOへ変換する
     *
     * @param dto ユースケースDTO
     * @return レスポンスDTO
     */
    public static SnsPlatformListResponse convertFrom(SnsPlatformListItemDto dto) {
        return new SnsPlatformListResponse(dto.getNames());
    }
}
