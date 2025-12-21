package com.example.keirekipro.usecase.certification.dto;

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
public class CertificationListUseCaseDto {

    private final List<String> names;

    /**
     * ファクトリーメソッド
     */
    public static CertificationListUseCaseDto create(List<String> names) {
        return new CertificationListUseCaseDto(names);
    }
}
