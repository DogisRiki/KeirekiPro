package com.example.keirekipro.presentation.snsplatform.dto;

import java.util.List;

import com.example.keirekipro.usecase.snsplatform.dto.SnsPlatformListUseCaseDto;

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
    public static SnsPlatformListResponse convertFrom(SnsPlatformListUseCaseDto dto) {
        return new SnsPlatformListResponse(dto.getNames());
    }
}
