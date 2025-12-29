package com.example.keirekipro.unit.shared.utils;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import javax.imageio.ImageIO;

import com.example.keirekipro.shared.utils.FileUtil;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.web.multipart.MultipartFile;

@ExtendWith(MockitoExtension.class)
class FileUtilTest {

    @Mock
    private MultipartFile mockFile;

    @Test
    @DisplayName("isFileSizeValid_ファイルサイズが最大値を超えている場合はfalseを返す")
    public void test1() {
        // 準備
        MockMultipartFile file = new MockMultipartFile(
                "testFile",
                "test.txt",
                "text/plain",
                "テストコンテンツ".getBytes());
        long maxFileSize = 5L; // 5バイト

        // 実行
        boolean result = FileUtil.isFileSizeValid(file, maxFileSize);

        // 検証
        assertThat(result).isFalse();
    }

    @Test
    @DisplayName("isFileSizeValid_ファイルサイズが最大値以下の場合はtrueを返す")
    public void test2() {
        // 準備
        MockMultipartFile file = new MockMultipartFile(
                "testFile",
                "test.txt",
                "text/plain",
                "テスト".getBytes());
        long maxFileSize = 100L; // 100バイト

        // 実行
        boolean result = FileUtil.isFileSizeValid(file, maxFileSize);

        // 検証
        assertThat(result).isTrue();
    }

    @Test
    @DisplayName("isExtensionValid_許可されていない拡張子の場合はfalseを返す")
    public void test3() {
        // 準備
        MockMultipartFile file = new MockMultipartFile(
                "testFile",
                "test.txt",
                "text/plain",
                "テストコンテンツ".getBytes());
        List<String> allowedExtensions = Arrays.asList("jpg", "png", "gif");

        // 実行
        boolean result = FileUtil.isExtensionValid(file, allowedExtensions);

        // 検証
        assertThat(result).isFalse();
    }

    @Test
    @DisplayName("isExtensionValid_許可された拡張子の場合はtrueを返す")
    public void test4() {
        // 準備
        MockMultipartFile file = new MockMultipartFile(
                "testFile",
                "test.jpg",
                "image/jpeg",
                "テストコンテンツ".getBytes());
        List<String> allowedExtensions = Arrays.asList("jpg", "png", "gif");

        // 実行
        boolean result = FileUtil.isExtensionValid(file, allowedExtensions);

        // 検証
        assertThat(result).isTrue();
    }

    @Test
    @DisplayName("isExtensionValid_ファイル名がnullの場合はfalseを返す")
    public void test5() {
        // 準備
        when(mockFile.getOriginalFilename()).thenReturn(null);
        List<String> allowedExtensions = Arrays.asList("jpg", "png", "gif");

        // 実行
        boolean result = FileUtil.isExtensionValid(mockFile, allowedExtensions);

        // 検証
        assertThat(result).isFalse();
    }

    @Test
    @DisplayName("isExtensionValid_ファイル名に拡張子がない場合はfalseを返す")
    public void test6() {
        // 準備
        when(mockFile.getOriginalFilename()).thenReturn("testfile");
        List<String> allowedExtensions = Arrays.asList("jpg", "png", "gif");

        // 実行
        boolean result = FileUtil.isExtensionValid(mockFile, allowedExtensions);

        // 検証
        assertThat(result).isFalse();
    }

    @Test
    @DisplayName("isMimeTypeValid_許可されていないMIMEタイプの場合はfalseを返す")
    public void test7() {
        // 準備
        MockMultipartFile file = new MockMultipartFile(
                "testFile",
                "test.txt",
                "text/plain",
                "テストコンテンツ".getBytes());
        List<String> allowedMimeTypes = Arrays.asList("image/jpeg", "image/png", "image/gif");

        // 実行
        boolean result = FileUtil.isMimeTypeValid(file, allowedMimeTypes);

        // 検証
        assertThat(result).isFalse();
    }

    @Test
    @DisplayName("isMimeTypeValid_許可されたMIMEタイプの場合はtrueを返す")
    public void test8() {
        // 準備
        MockMultipartFile file = new MockMultipartFile(
                "testFile",
                "test.jpg",
                "image/jpeg",
                "テストコンテンツ".getBytes());
        List<String> allowedMimeTypes = Arrays.asList("image/jpeg", "image/png", "image/gif");

        // 実行
        boolean result = FileUtil.isMimeTypeValid(file, allowedMimeTypes);

        // 検証
        assertThat(result).isTrue();
    }

    @Test
    @DisplayName("isMimeTypeValid_MIMEタイプがnullの場合はfalseを返す")
    public void test9() {
        // 準備
        when(mockFile.getContentType()).thenReturn(null);
        List<String> allowedMimeTypes = Arrays.asList("image/jpeg", "image/png", "image/gif");

        // 実行
        boolean result = FileUtil.isMimeTypeValid(mockFile, allowedMimeTypes);

        // 検証
        assertThat(result).isFalse();
    }

    @Test
    @DisplayName("isMimeTypeValid_空のMIMEタイプリストが渡された場合はfalseを返す")
    public void test10() {
        // 準備
        MockMultipartFile file = new MockMultipartFile(
                "testFile",
                "test.jpg",
                "image/jpeg",
                "テストコンテンツ".getBytes());
        List<String> allowedMimeTypes = Collections.emptyList();

        // 実行
        boolean result = FileUtil.isMimeTypeValid(file, allowedMimeTypes);

        // 検証
        assertThat(result).isFalse();
    }

    @Test
    @DisplayName("isImageReadValid_有効な画像ファイルの場合はtrueを返す")
    public void test11() throws IOException {
        // 準備: 1x1の正方形の画像を作成
        BufferedImage image = new BufferedImage(1, 1, BufferedImage.TYPE_INT_RGB);
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        ImageIO.write(image, "jpg", baos);
        byte[] imageBytes = baos.toByteArray();

        MockMultipartFile file = new MockMultipartFile(
                "testFile",
                "test.jpg",
                "image/jpeg",
                imageBytes);

        // 実行
        boolean result = FileUtil.isImageReadValid(file);

        // 検証
        assertThat(result).isTrue();
    }

    @Test
    @DisplayName("isImageReadValid_画像ではないファイルの場合はfalseを返す")
    public void test12() {
        // 準備
        MockMultipartFile file = new MockMultipartFile(
                "testFile",
                "test.txt",
                "text/plain",
                "noImage".getBytes());

        // 実行
        boolean result = FileUtil.isImageReadValid(file);

        // 検証
        assertThat(result).isFalse();
    }

    @Test
    @DisplayName("isImageReadValid_画像読み込み時にIOExceptionが発生した場合はfalseを返す")
    public void test13() throws IOException {
        // 準備
        when(mockFile.getInputStream()).thenThrow(new IOException("テスト用例外"));

        // 実行
        boolean result = FileUtil.isImageReadValid(mockFile);

        // 検証
        assertThat(result).isFalse();
    }

    @Test
    @DisplayName("sanitizeFileName_正常なファイル名はそのまま返す")
    public void test14() {
        // 実行
        String result = FileUtil.sanitizeFileName("my_resume", "default");

        // 検証
        assertThat(result).isEqualTo("my_resume");
    }

    @Test
    @DisplayName("sanitizeFileName_nullの場合はデフォルト名を返す")
    public void test15() {
        // 実行
        String result = FileUtil.sanitizeFileName(null, "default");

        // 検証
        assertThat(result).isEqualTo("default");
    }

    @Test
    @DisplayName("sanitizeFileName_空白のみの場合はデフォルト名を返す")
    public void test16() {
        // 実行
        String result = FileUtil.sanitizeFileName("   ", "default");

        // 検証
        assertThat(result).isEqualTo("default");
    }

    @Test
    @DisplayName("sanitizeFileName_禁止文字は_に置換される")
    public void test17() {
        // 実行
        String result = FileUtil.sanitizeFileName("file\\name/test:file*name?test\"file<name>test|end", "default");

        // 検証
        assertThat(result).isEqualTo("file_name_test_file_name_test_file_name_test_end");
    }

    @Test
    @DisplayName("sanitizeFileName_制御文字は除去される")
    public void test18() {
        // 実行
        String result = FileUtil.sanitizeFileName("file\tname\ntest", "default");

        // 検証
        assertThat(result).isEqualTo("filenametest");
    }

    @Test
    @DisplayName("sanitizeFileName_禁止文字のみで構成される場合はデフォルト名を返す")
    public void test19() {
        // 実行
        String result = FileUtil.sanitizeFileName("\\/:*?\"<>|", "default");

        // 検証
        assertThat(result).isEqualTo("default");
    }

    @Test
    @DisplayName("sanitizeFileName_255文字を超える場合は255文字に切り捨てる")
    public void test20() {
        // 準備
        String longName = "a".repeat(300);

        // 実行
        String result = FileUtil.sanitizeFileName(longName, "default");

        // 検証
        assertThat(result).hasSize(255);
        assertThat(result).isEqualTo("a".repeat(255));
    }

    @Test
    @DisplayName("sanitizeFileName_前後の空白はトリムされる")
    public void test21() {
        // 実行
        String result = FileUtil.sanitizeFileName("  filename  ", "default");

        // 検証
        assertThat(result).isEqualTo("filename");
    }

    @Test
    @DisplayName("getExtension_拡張子を小文字で返す")
    public void test22() {
        MockMultipartFile file = new MockMultipartFile(
                "testFile",
                "test.PNG",
                "image/png",
                "dummy".getBytes());

        // 実行
        String result = FileUtil.getExtension(file);

        // 検証
        assertThat(result).isEqualTo("png");
    }

    @Test
    @DisplayName("getExtension_ファイル名がnullの場合は空文字を返す")
    public void test23() {
        when(mockFile.getOriginalFilename()).thenReturn(null);

        // 実行
        String result = FileUtil.getExtension(mockFile);

        // 検証
        assertThat(result).isEqualTo("");
    }

    @Test
    @DisplayName("getExtension_拡張子がない場合は空文字を返す")
    public void test24() {
        when(mockFile.getOriginalFilename()).thenReturn("testfile");

        // 実行
        String result = FileUtil.getExtension(mockFile);

        // 検証
        assertThat(result).isEqualTo("");
    }

}
