package com.example.keirekipro.usecase.query.certification;

import com.example.keirekipro.usecase.query.certification.dto.CertificationListQueryDto;

/**
 * 資格一覧取得クエリインターフェース
 */
public interface CertificationListQuery {

    /**
     * 資格一覧を取得する
     *
     * @return 資格一覧クエリDTO
     */
    CertificationListQueryDto findAll();
}
