package com.example.keirekipro.infrastructure.shared.pdf;

/**
 * HTMLからPDFへの変換を抽象化するインターフェース
 */
public interface HtmlToPdfRenderer {

    /**
     * HTMLをPDFに変換する
     *
     * @param html HTML文字列
     * @return PDFバイト列
     */
    byte[] render(String html);
}
