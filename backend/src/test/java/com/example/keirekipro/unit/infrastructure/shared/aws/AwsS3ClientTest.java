package com.example.keirekipro.unit.infrastructure.shared.aws;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.net.URI;
import java.time.Duration;

import com.example.keirekipro.config.YamlPropertySourceFactory;
import com.example.keirekipro.infrastructure.shared.aws.AwsS3Client;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.junit.jupiter.SpringJUnitConfig;
import org.springframework.web.multipart.MultipartFile;

import lombok.RequiredArgsConstructor;

import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectResponse;
import software.amazon.awssdk.services.s3.model.S3Exception;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;
import software.amazon.awssdk.services.s3.presigner.model.PresignedGetObjectRequest;

@SpringJUnitConfig(AwsS3ClientTest.TestConfig.class)
@TestPropertySource(locations = "classpath:application-test.yaml", factory = YamlPropertySourceFactory.class)
@ActiveProfiles("test")
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
@ExtendWith(MockitoExtension.class)
class AwsS3ClientTest {

    private final AwsS3Client awsS3Client;

    @Mock
    private S3Client s3Client;

    @Test
    @DisplayName("@PostConstructによりAwsS3Clientが正しくインスタンス化される")
    void test1() {
        // プロパティがバインドされている
        assertThat(awsS3Client.getRegion()).isEqualTo("ap-northeast-1");
        assertThat(awsS3Client.getEndpoint()).isEqualTo("http://localhost:4566");
        assertThat(awsS3Client.getBucketName()).isEqualTo("test-bucket");

        // S3Clientのインスタンスが存在し、正しい
        assertThat(awsS3Client.getS3Client())
                .isNotNull()
                .isInstanceOf(S3Client.class);
    }

    @Test
    @DisplayName("uploadFileメソッドでファイルを保存すると、保存先のキーが返される")
    void test2() throws IOException {
        // テスト対象のAwsS3Clientの内部依存をモックに上書き
        awsS3Client.setS3Client(s3Client);
        awsS3Client.setBucketName("test-bucket");

        // テストデータ
        MultipartFile file = new MockMultipartFile(
                "test.jpg",
                "original.jpg",
                "image/jpeg",
                "test image content".getBytes());

        // モックをセットアップ
        when(s3Client.putObject(any(PutObjectRequest.class), any(RequestBody.class)))
                .thenReturn(PutObjectResponse.builder().build());

        // リクエストキャプチャ
        ArgumentCaptor<PutObjectRequest> requestCaptor = ArgumentCaptor.forClass(PutObjectRequest.class);

        // 実行
        String key = awsS3Client.uploadFile(file, "test/");

        // 検証
        verify(s3Client).putObject(requestCaptor.capture(), any(RequestBody.class));

        // キャプチャしたリクエストの検証
        PutObjectRequest capturedRequest = requestCaptor.getValue();
        assertThat(capturedRequest.bucket()).isEqualTo("test-bucket");
        assertThat(capturedRequest.key()).isEqualTo(key);
        assertThat(capturedRequest.contentType()).isEqualTo("image/jpeg");

        // キーの形式検証
        assertThat(key).startsWith("test/");
        assertThat(key).endsWith(".jpg");
    }

    @Test
    @DisplayName("uploadFileWithNameメソッドでファイルを保存すると、保存先のキーが返される")
    void test3() throws IOException {
        // テスト対象のAwsS3Clientの内部依存をモックに上書き
        awsS3Client.setS3Client(s3Client);
        awsS3Client.setBucketName("test-bucket");

        // テストデータ
        MultipartFile file = new MockMultipartFile(
                "test.pdf",
                "original.pdf",
                "application/pdf",
                "test pdf content".getBytes());
        String fileName = "s3-test.pdf";

        // モックをセットアップ
        when(s3Client.putObject(any(PutObjectRequest.class), any(RequestBody.class)))
                .thenReturn(PutObjectResponse.builder().build());

        // リクエストキャプチャ
        ArgumentCaptor<PutObjectRequest> requestCaptor = ArgumentCaptor.forClass(PutObjectRequest.class);

        // 実行
        String key = awsS3Client.uploadFileWithName(file, "documents/", fileName);

        // 検証
        verify(s3Client).putObject(requestCaptor.capture(), any(RequestBody.class));

        // キャプチャしたリクエストの検証
        PutObjectRequest capturedRequest = requestCaptor.getValue();
        assertThat(capturedRequest.bucket()).isEqualTo("test-bucket");
        assertThat(capturedRequest.key()).isEqualTo("documents/s3-test.pdf");
        assertThat(capturedRequest.contentType()).isEqualTo("application/pdf");

        // キーの形式検証
        assertThat(key).isEqualTo("documents/s3-test.pdf");
    }

    @Test
    @DisplayName("S3からファイルを取得すると、正しくバイト配列が返される")
    void test4() throws IOException {
        // テスト対象のAwsS3Clientの内部依存をモックに上書き
        awsS3Client.setS3Client(s3Client);
        awsS3Client.setBucketName("test-bucket");

        // テストデータ
        byte[] testData = "test file content".getBytes();
        String key = "test/file.txt";

        // モックのレスポンス設定
        GetObjectResponse response = GetObjectResponse.builder()
                .contentType("text/plain")
                .build();

        ResponseInputStream<GetObjectResponse> responseStream = new ResponseInputStream<>(response,
                new ByteArrayInputStream(testData));

        // モックの動作設定
        when(s3Client.getObject(any(GetObjectRequest.class))).thenReturn(responseStream);

        // リクエストキャプチャ
        ArgumentCaptor<GetObjectRequest> requestCaptor = ArgumentCaptor.forClass(GetObjectRequest.class);

        // 実行
        byte[] result = awsS3Client.getFileAsBytes(key);

        // 検証
        verify(s3Client).getObject(requestCaptor.capture());

        // キャプチャしたリクエストの検証
        GetObjectRequest capturedRequest = requestCaptor.getValue();
        assertThat(capturedRequest.bucket()).isEqualTo("test-bucket");
        assertThat(capturedRequest.key()).isEqualTo(key);

        // 結果の検証
        assertThat(result).isEqualTo(testData);
    }

    @Test
    @DisplayName("S3からオブジェクトを削除できる")
    void test5() {
        // テスト対象のAwsS3Clientの内部依存をモックに上書き
        awsS3Client.setS3Client(s3Client);
        awsS3Client.setBucketName("test-bucket");

        // テストデータ
        String key = "test/test.jpg";

        // リクエストキャプチャ
        ArgumentCaptor<DeleteObjectRequest> requestCaptor = ArgumentCaptor.forClass(DeleteObjectRequest.class);

        // 実行
        assertThatCode(() -> {
            awsS3Client.deleteObject(key);
        }).doesNotThrowAnyException();

        // 検証
        verify(s3Client).deleteObject(requestCaptor.capture());

        // キャプチャしたリクエストの検証
        DeleteObjectRequest capturedRequest = requestCaptor.getValue();
        assertThat(capturedRequest.bucket()).isEqualTo("test-bucket");
        assertThat(capturedRequest.key()).isEqualTo(key);
    }

    @Test
    @DisplayName("S3操作でエラーが発生した場合、例外が適切に伝播される")
    void test6() throws IOException {
        // テスト対象のAwsS3Clientの内部依存をモックに上書き
        awsS3Client.setS3Client(s3Client);
        awsS3Client.setBucketName("test-bucket");

        // テストデータ
        String key = "test/non-existent-file.txt";

        // モックをセットアップ
        when(s3Client.getObject(any(GetObjectRequest.class)))
                .thenThrow(S3Exception.builder().message("File not found").build());

        // 実行と検証
        assertThatThrownBy(() -> awsS3Client.getFileAsBytes(key))
                .isInstanceOf(S3Exception.class)
                .hasMessageContaining("File not found");
    }

    @Test
    @DisplayName("generatePresignedUrlメソッドで署名付きURLが生成される")
    void test7() throws Exception {
        // モック化した PresignedGetObjectRequest を作成
        PresignedGetObjectRequest presignedRequest = mock(PresignedGetObjectRequest.class);
        when(presignedRequest.url())
                .thenReturn(URI.create("https://signed-url.test/file.png").toURL());

        // S3Presigner モックを作成し、presignGetObject をスタブ
        S3Presigner presignerMock = mock(S3Presigner.class);
        when(presignerMock.presignGetObject(any(GetObjectPresignRequest.class)))
                .thenReturn(presignedRequest);

        // テスト対象 AwsS3Client にモックを注入
        awsS3Client.setS3Presigner(presignerMock);

        // 実行
        String resultUrl = awsS3Client.generatePresignedUrl("path/to/file.png", Duration.ofMinutes(10));

        // 検証
        assertThat(resultUrl).isEqualTo("https://signed-url.test/file.png");
    }

    @TestConfiguration
    @EnableConfigurationProperties(AwsS3Client.class)
    static class TestConfig {
    }
}
