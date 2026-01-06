package com.example.keirekipro.usecase.resume.policy;

import lombok.AccessLevel;
import lombok.NoArgsConstructor;

/**
 * 職務経歴書バックアップバージョン
 */
@NoArgsConstructor(access = AccessLevel.PRIVATE)
public final class ResumeBackupVersion {

    /**
     * サポートするバックアップバージョン
     */
    public static final String SUPPORTED_VERSION = "1.0";
}
