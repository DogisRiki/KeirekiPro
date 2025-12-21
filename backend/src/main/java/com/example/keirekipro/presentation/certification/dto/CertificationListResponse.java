package com.example.keirekipro.presentation.certification.dto;

import java.util.List;

import com.example.keirekipro.usecase.query.certification.dto.CertificationListItemDto;

import lombok.AccessLevel;
import lombok.EqualsAndHashCode;
import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * 資格一覧レスポンス
 */
@Getter
@EqualsAndHashCode
@RequiredArgsConstructor(access = AccessLevel.PRIVATE)
public class CertificationListResponse {

    private final List<String> names;

    /**
     * ユースケースDTOからレスポンスDTOへ変換する
     *
     * @param dto ユースケースDTO
     * @return レスポンスDTO
     */
    public static CertificationListResponse convertFrom(CertificationListItemDto dto) {
        return new CertificationListResponse(dto.getNames());
    }
}
