package com.example.keirekipro.usecase.resume.dto;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * エクスポート結果を保持するユースケースDTO
 */
@Getter
@RequiredArgsConstructor
public class ExportResumeUseCaseDto {

    /**
     * ファイル名（職務経歴書名 + 拡張子）
     */
    private final String fileName;

    /**
     * Content-Type
     */
    private final String contentType;

    /**
     * ファイルデータ
     */
    private final byte[] content;
}
