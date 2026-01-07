package com.example.keirekipro.presentation.certification.dto;

import java.util.List;

import com.example.keirekipro.usecase.query.certification.dto.CertificationListQueryDto;

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
     * クエリDTOからレスポンスDTOへ変換する
     *
     * @param dto クエリDTO
     * @return レスポンスDTO
     */
    public static CertificationListResponse convertFrom(CertificationListQueryDto dto) {
        return new CertificationListResponse(dto.getNames());
    }
}
