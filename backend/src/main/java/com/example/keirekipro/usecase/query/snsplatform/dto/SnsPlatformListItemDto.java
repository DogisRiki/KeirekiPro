package com.example.keirekipro.usecase.query.snsplatform.dto;

import java.util.List;

import lombok.AccessLevel;
import lombok.EqualsAndHashCode;
import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * SNSプラットフォーム一覧ユースケースDTO
 *
 * 画面入力補助用のマスタ一覧を表現するQueryモデル
 */
@Getter
@EqualsAndHashCode
@RequiredArgsConstructor(access = AccessLevel.PRIVATE)
public class SnsPlatformListItemDto {

    private final List<String> names;

    /**
     * ファクトリーメソッド
     */
    public static SnsPlatformListItemDto create(List<String> names) {
        return new SnsPlatformListItemDto(names);
    }
}
