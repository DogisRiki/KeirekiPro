package com.example.keirekipro.usecase.query.snsplatform.dto;

import java.util.List;

import lombok.Builder;
import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * SNSプラットフォーム一覧クエリDTO
 */
@Getter
@Builder
@RequiredArgsConstructor
public class SnsPlatformListQueryDto {

    private final List<String> names;
}
