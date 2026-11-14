// PresignExpected は、Java 版の S3ObjectStore と同じ AWS SDK for Java の S3Presigner で、プロフィール画像の GET の要求に
// 600秒の URL を署名し、標準出力に1行で書く。Go 版の objectstore_test.go の TestPresign_MatchesJava は、この URL を正解として読む。
//
// S3Presigner の設定は、Java 版の開発環境の application-dev.yaml と、Spring Cloud AWS の S3 の自動設定が作る S3Presigner と同じにする。
//   - 接続先: http://localstack:4566
//   - 地域: ap-northeast-1
//   - 資格情報: dummy / dummy
//   - パスの形: path-style-access-enabled: true
//   - 置き場所: keirekipro-storage
//   - 画像の名前: /profile/image/ で始まる名前(ProfileImageKeys.PREFIX)
// URL のホストは、LocalstackPresignedUrlTransformer が localhost に置き換える前の localstack:4566 のままにする。
//
// 使い方(作業フォルダの最上位で、1行で打つ):
//   bash .claude/scripts/parallel/run-check.sh --wait backend sh -c './gradlew -q dependencies --configuration runtimeClasspath | grep "software.amazon.awssdk:s3:" | head -1 && ./gradlew -q bootJar && java --class-path "$(find ~/.gradle/caches/modules-2/files-2.1/software.amazon.awssdk -name "*-2.57.0.jar" | tr "\n" ":")$(find ~/.gradle/caches/modules-2/files-2.1 -path "*reactive-streams*" -name "*.jar" | head -1):$(find ~/.gradle/caches/modules-2/files-2.1/org.slf4j/slf4j-api -name "*.jar" | head -1)" internal/users/testdata/presign/PresignExpected.java > internal/users/testdata/presign/expected_url.txt'
// 1つ目のコマンドは、Java 版が使う AWS SDK for Java の版を出す。版が 2.57.0 でなければ、2つの find の版を書き換える。
// 2つ目のコマンドは、Java 版の実行に要る jar をすべて Gradle の置き場に取ってくる。
// 3つ目のコマンドは、このファイルを1つのソースのファイルとして動かし、出た URL を expected_url.txt に書く。
// URL の X-Amz-Date は、動かした時刻になる。Go のテストは、この時刻を署名の時刻として使うので、動かし直しても通る。

import java.net.URI;
import java.time.Duration;

import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;

public class PresignExpected {

    public static void main(String[] args) {
        try (S3Presigner presigner = S3Presigner.builder()
                .region(Region.of("ap-northeast-1"))
                .credentialsProvider(StaticCredentialsProvider.create(AwsBasicCredentials.create("dummy", "dummy")))
                .endpointOverride(URI.create("http://localstack:4566"))
                .serviceConfiguration(S3Configuration.builder().pathStyleAccessEnabled(true).build())
                .build()) {
            GetObjectRequest get = GetObjectRequest.builder()
                    .bucket("keirekipro-storage")
                    .key("/profile/image/0b6f3c2e-6a1d-4f7e-9c58-2d4a7e1b9f03.png")
                    .build();
            GetObjectPresignRequest req = GetObjectPresignRequest.builder()
                    .signatureDuration(Duration.ofSeconds(600))
                    .getObjectRequest(get)
                    .build();
            System.out.println(presigner.presignGetObject(req).url().toString());
        }
    }
}
