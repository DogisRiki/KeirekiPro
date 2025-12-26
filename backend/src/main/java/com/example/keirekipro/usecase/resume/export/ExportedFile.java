package com.example.keirekipro.usecase.resume.export;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * Exporterポートの戻り値を表すモデル
 */
@Getter
@RequiredArgsConstructor
public class ExportedFile {

    /**
     * ファイル名
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
