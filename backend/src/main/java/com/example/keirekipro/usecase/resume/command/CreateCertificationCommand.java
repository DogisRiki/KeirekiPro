package com.example.keirekipro.usecase.resume.command;

import java.time.YearMonth;
import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * 資格作成ユースケースの入力コマンド
 */
@Data
@AllArgsConstructor
public class CreateCertificationCommand {

    private UUID userId;

    private String resumeId;

    private String name;

    private YearMonth date;
}
