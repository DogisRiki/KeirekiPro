package com.example.keirekipro.infrastructure.query.snsplatform;

import java.util.List;
import java.util.stream.Collectors;

import com.example.keirekipro.usecase.query.snsplatform.dto.SnsPlatformListItemDto;

import org.springframework.stereotype.Repository;

import lombok.RequiredArgsConstructor;

/**
 * SNSプラットフォーム一覧取得クエリ
 */
@Repository
@RequiredArgsConstructor
public class SnsPlatformQuery {

    private final SnsPlatformMapper snsPlatformMapper;

    /**
     * SNSプラットフォーム一覧を取得して整形して返却する
     *
     * @return SNSプラットフォーム一覧DTO
     */
    public SnsPlatformListItemDto selectSnsPlatformListItem() {

        List<SnsPlatformDto> rows = snsPlatformMapper.selectAll();

        List<String> names = rows.stream()
                .map(SnsPlatformDto::getName)
                .collect(Collectors.toList());

        return SnsPlatformListItemDto.create(names);
    }
}
