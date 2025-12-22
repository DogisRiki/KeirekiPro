package com.example.keirekipro.usecase.query.certification;

import com.example.keirekipro.infrastructure.query.certification.CertificationQuery;
import com.example.keirekipro.usecase.query.certification.dto.CertificationListItemDto;

import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * 資格一覧取得クエリサービス
 */
@Service
@RequiredArgsConstructor
public class GetCertificationListQueryService {

    private final CertificationQuery certificationQuery;

    /**
     * 資格一覧取得クエリサービスを実行する
     *
     * @return 資格一覧クエリDTO
     */
    public CertificationListItemDto execute() {
        return certificationQuery.selectCertificationListItem();
    }
}
