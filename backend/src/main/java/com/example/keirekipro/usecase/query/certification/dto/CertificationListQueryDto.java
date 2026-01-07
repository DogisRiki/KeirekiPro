package com.example.keirekipro.usecase.query.certification.dto;

import java.util.List;

import lombok.Builder;
import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * 資格一覧クエリDTO
 */
@Getter
@Builder
@RequiredArgsConstructor
public class CertificationListQueryDto {

    private final List<String> names;
}
