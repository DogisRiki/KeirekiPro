package com.example.keirekipro.unit.infrastructure.shared.aws.s3;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.time.Duration;

import com.example.keirekipro.infrastructure.shared.aws.config.AwsS3Properties;
import com.example.keirekipro.infrastructure.shared.aws.s3.PresignedUrlTransformer;
import com.example.keirekipro.infrastructure.shared.aws.s3.S3ObjectStore;
import com.example.keirekipro.usecase.shared.store.StoredObject;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectResponse;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;
import software.amazon.awssdk.services.s3.presigner.model.PresignedGetObjectRequest;

@ExtendWith(MockitoExtension.class)
class S3ObjectStoreTest {

    @Mock
    private AwsS3Properties properties;

    @Mock
    private S3Client s3Client;

    @Mock
    private S3Presigner s3Presigner;

    @Mock
    private PresignedUrlTransformer presignedUrlTransformer;

    private S3ObjectStore objectStore;

    @BeforeEach
    void setUp() {
        when(properties.getBucketName()).thenReturn("test-bucket");
        objectStore = new S3ObjectStore(properties, s3Client, s3Presigner, presignedUrlTransformer);
    }

    @Test
    @DisplayName("put_保存すると、prefix + UUID + 拡張子のキーが返り、PutObjectRequestが正しく構築される")
    void test1() {
        when(s3Client.putObject(any(PutObjectRequest.class), any(RequestBody.class)))
                .thenReturn(PutObjectResponse.builder().build());

        StoredObject obj = new StoredObject("content".getBytes(), "image/png", "photo.png");

        String key = objectStore.put(obj, "profile/");

        assertThat(key).startsWith("profile/");
        assertThat(key).endsWith(".png");

        ArgumentCaptor<PutObjectRequest> captor = ArgumentCaptor.forClass(PutObjectRequest.class);
        verify(s3Client).putObject(captor.capture(), any(RequestBody.class));

        PutObjectRequest req = captor.getValue();
        assertThat(req.bucket()).isEqualTo("test-bucket");
        assertThat(req.key()).isEqualTo(key);
        assertThat(req.contentType()).isEqualTo("image/png");
        assertThat(req.metadata()).containsEntry("Original-Filename", "photo.png");
    }

    @Test
    @DisplayName("putAs_保存すると、prefix + fileName のキーが返り、PutObjectRequestが正しく構築される")
    void test2() {
        when(s3Client.putObject(any(PutObjectRequest.class), any(RequestBody.class)))
                .thenReturn(PutObjectResponse.builder().build());

        StoredObject obj = new StoredObject("content".getBytes(), "application/pdf", "original.pdf");

        String key = objectStore.putAs(obj, "documents/", "fixed-name.pdf");

        assertThat(key).isEqualTo("documents/fixed-name.pdf");

        ArgumentCaptor<PutObjectRequest> captor = ArgumentCaptor.forClass(PutObjectRequest.class);
        verify(s3Client).putObject(captor.capture(), any(RequestBody.class));

        PutObjectRequest req = captor.getValue();
        assertThat(req.bucket()).isEqualTo("test-bucket");
        assertThat(req.key()).isEqualTo("documents/fixed-name.pdf");
        assertThat(req.contentType()).isEqualTo("application/pdf");
        assertThat(req.metadata()).containsEntry("Original-Filename", "original.pdf");
    }

    @Test
    @DisplayName("getBytes_S3から取得すると、正しくバイト配列が返される")
    void test3() throws Exception {
        byte[] testData = "test file content".getBytes();
        String key = "path/to/file.txt";

        GetObjectResponse response = GetObjectResponse.builder().contentType("text/plain").build();
        ResponseInputStream<GetObjectResponse> stream = new ResponseInputStream<>(
                response,
                new ByteArrayInputStream(testData));

        when(s3Client.getObject(any(GetObjectRequest.class))).thenReturn(stream);

        byte[] result = objectStore.getBytes(key);

        assertThat(result).isEqualTo(testData);

        ArgumentCaptor<GetObjectRequest> captor = ArgumentCaptor.forClass(GetObjectRequest.class);
        verify(s3Client).getObject(captor.capture());
        assertThat(captor.getValue().bucket()).isEqualTo("test-bucket");
        assertThat(captor.getValue().key()).isEqualTo(key);
    }

    @Test
    @DisplayName("getBytes_読み取り中にIOExceptionが発生した場合、RuntimeExceptionがスローされる")
    void test4() {
        String key = "path/to/broken.txt";

        InputStream broken = new InputStream() {
            @Override
            public int read() throws IOException {
                throw new IOException("broken");
            }
        };

        GetObjectResponse response = GetObjectResponse.builder().build();
        ResponseInputStream<GetObjectResponse> stream = new ResponseInputStream<>(response, broken);

        when(s3Client.getObject(any(GetObjectRequest.class))).thenReturn(stream);

        assertThatThrownBy(() -> objectStore.getBytes(key))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining(key);
    }

    @Test
    @DisplayName("delete_S3オブジェクトが削除される")
    void test5() {
        String key = "path/to/delete.png";

        assertThatCode(() -> objectStore.delete(key)).doesNotThrowAnyException();

        ArgumentCaptor<DeleteObjectRequest> captor = ArgumentCaptor.forClass(DeleteObjectRequest.class);
        verify(s3Client).deleteObject(captor.capture());
        assertThat(captor.getValue().bucket()).isEqualTo("test-bucket");
        assertThat(captor.getValue().key()).isEqualTo(key);
    }

    @Test
    @DisplayName("issueGetUrl_署名付きURLが生成され、変換戦略が適用される")
    void test6() throws Exception {
        String key = "path/to/file.png";
        Duration ttl = Duration.ofMinutes(10);

        PresignedGetObjectRequest presigned = org.mockito.Mockito.mock(PresignedGetObjectRequest.class);
        when(presigned.url()).thenReturn(URI.create("https://signed-url.test/file.png").toURL());

        when(s3Presigner.presignGetObject(any(GetObjectPresignRequest.class))).thenReturn(presigned);
        when(presignedUrlTransformer.transform("https://signed-url.test/file.png")).thenReturn("TRANSFORMED");

        String result = objectStore.issueGetUrl(key, ttl);

        assertThat(result).isEqualTo("TRANSFORMED");
        verify(presignedUrlTransformer).transform("https://signed-url.test/file.png");

        ArgumentCaptor<GetObjectPresignRequest> captor = ArgumentCaptor.forClass(GetObjectPresignRequest.class);
        verify(s3Presigner).presignGetObject(captor.capture());

        GetObjectPresignRequest req = captor.getValue();
        assertThat(req.signatureDuration()).isEqualTo(ttl);
        assertThat(req.getObjectRequest().bucket()).isEqualTo("test-bucket");
        assertThat(req.getObjectRequest().key()).isEqualTo(key);
    }
}
