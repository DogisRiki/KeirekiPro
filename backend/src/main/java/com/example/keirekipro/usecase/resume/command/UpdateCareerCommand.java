package com.example.keirekipro.usecase.resume.command;

import java.time.YearMonth;
import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * 職歴更新ユースケースの入力コマンド
 */
@Data
@AllArgsConstructor
public class UpdateCareerCommand {

    private UUID userId;

    private String resumeId;

    private UUID careerId;

    private String companyName;

    private YearMonth startDate;

    private YearMonth endDate;

    private Boolean active;
}
