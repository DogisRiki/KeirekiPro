package com.example.keirekipro.usecase.query.certification.dto;

import java.util.List;

import lombok.AccessLevel;
import lombok.EqualsAndHashCode;
import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * 資格一覧ユースケースDTO
 *
 * 画面入力補助用のマスタ一覧を表現するQueryモデル
 */
@Getter
@EqualsAndHashCode
@RequiredArgsConstructor(access = AccessLevel.PRIVATE)
public class CertificationListItemDto {

    private final List<String> names;

    /**
     * ファクトリーメソッド
     */
    public static CertificationListItemDto create(List<String> names) {
        return new CertificationListItemDto(names);
    }
}
