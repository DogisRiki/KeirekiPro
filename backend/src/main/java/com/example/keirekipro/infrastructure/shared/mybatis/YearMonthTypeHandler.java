package com.example.keirekipro.infrastructure.shared.mybatis;

import java.sql.CallableStatement;
import java.sql.Date;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.YearMonth;

import org.apache.ibatis.type.BaseTypeHandler;
import org.apache.ibatis.type.JdbcType;

/**
 * YearMonthをDATE型として扱うタイプハンドラー
 */
public class YearMonthTypeHandler extends BaseTypeHandler<YearMonth> {

    @Override
    public void setNonNullParameter(PreparedStatement ps, int i, YearMonth parameter, JdbcType jdbcType)
            throws SQLException {
        // YearMonthをその月の1日としてLocalDateに変換し、java.sql.Dateにしてセット
        ps.setDate(i, Date.valueOf(parameter.atDay(1)));
    }

    @Override
    public YearMonth getNullableResult(ResultSet rs, String columnName) throws SQLException {
        Date d = rs.getDate(columnName);
        return (d != null) ? YearMonth.from(d.toLocalDate()) : null;
    }

    @Override
    public YearMonth getNullableResult(ResultSet rs, int columnIndex) throws SQLException {
        Date d = rs.getDate(columnIndex);
        return (d != null) ? YearMonth.from(d.toLocalDate()) : null;
    }

    @Override
    public YearMonth getNullableResult(CallableStatement cs, int columnIndex) throws SQLException {
        Date d = cs.getDate(columnIndex);
        return (d != null) ? YearMonth.from(d.toLocalDate()) : null;
    }
}
