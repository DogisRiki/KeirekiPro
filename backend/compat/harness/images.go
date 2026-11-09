//go:build compat

package harness

import (
	"archive/tar"
	"bytes"
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/moby/moby/client"
	"github.com/moby/patternmatcher"
	"github.com/moby/patternmatcher/ignorefile"
	"github.com/testcontainers/testcontainers-go"
)

// ImageSpec は、比べる検査が組み立てる1つのイメージである。
// Dockerfile と Context は、リポジトリの最上位からのパスで書く。
type ImageSpec struct {
	Name       string
	Dockerfile string
	Context    string
}

// 比べる検査が組み立てる6つのイメージの名前である。
const (
	ImageJava     = "java"
	ImageGo       = "go"
	ImagePostgres = "postgres"
	ImageRedis    = "redis"
	ImageFakeAWS  = "fakeaws"
	ImageFakeOIDC = "fakeoidc"
)

// ImageSpecs は、design.md の「イメージの組み立て方」の表の6つのイメージである。
var ImageSpecs = []ImageSpec{
	{Name: ImageJava, Dockerfile: "docker/backend/Dockerfile.prod", Context: "backend"},
	{Name: ImageGo, Dockerfile: "docker/backend-go/Dockerfile.prod", Context: "backend"},
	{Name: ImagePostgres, Dockerfile: "docker/db/Dockerfile", Context: "docker/db"},
	{Name: ImageRedis, Dockerfile: "docker/redis/Dockerfile", Context: "docker/redis"},
	{Name: ImageFakeAWS, Dockerfile: "backend/compat/fakeaws/Dockerfile", Context: "backend"},
	{Name: ImageFakeOIDC, Dockerfile: "backend/compat/fakeoidc/Dockerfile", Context: "backend"},
}

// archiveDockerfile は、組み立ての文脈の tar の中に Dockerfile を置く名前である。
// Dockerfile が組み立ての文脈の外にあるイメージ(Java 版と Go 版)があるので、docker build -f と同じく、
// どのイメージでも Dockerfile を文脈の最上位に別の名前で入れて送る。
const archiveDockerfile = ".compat-dockerfile"

// FindImageSpec は、名前のイメージの組み立て方を返す。
func FindImageSpec(name string) (ImageSpec, error) {
	for _, spec := range ImageSpecs {
		if spec.Name == name {
			return spec, nil
		}
	}
	return ImageSpec{}, fmt.Errorf("harness: イメージ %q の組み立て方がありません", name)
}

// BuildContextArchive は、組み立ての文脈のフォルダを、文脈の .dockerignore で除くファイルを除いて tar にし、
// Dockerfile を archiveDockerfile の名前で足して返す。docker build -f と同じ文脈を送るためである。
// .dockerignore そのものは送らない。除くファイルは、ここで除き終えているためである。
func BuildContextArchive(repoRoot string, spec ImageSpec) (*bytes.Reader, error) {
	contextDir := filepath.Join(repoRoot, filepath.FromSlash(spec.Context))
	matcher, err := readDockerignore(contextDir)
	if err != nil {
		return nil, err
	}
	dockerfile, err := os.ReadFile(filepath.Clean(filepath.Join(repoRoot, filepath.FromSlash(spec.Dockerfile))))
	if err != nil {
		return nil, fmt.Errorf("harness: イメージ %s の Dockerfile を読めません: %w", spec.Name, err)
	}

	var buf bytes.Buffer
	tw := tar.NewWriter(&buf)
	walkErr := filepath.WalkDir(contextDir, func(file string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(contextDir, file)
		if err != nil {
			return err
		}
		rel = filepath.ToSlash(rel)
		if rel == "." || rel == ".dockerignore" {
			return nil
		}
		excluded, err := matcher.MatchesOrParentMatches(rel)
		if err != nil {
			return fmt.Errorf("harness: %s を .dockerignore と照らせません: %w", rel, err)
		}
		if excluded {
			// 除いたフォルダの下に、! で戻すファイルが無ければ、フォルダの中を読まない
			if entry.IsDir() && !matcher.Exclusions() {
				return filepath.SkipDir
			}
			return nil
		}
		return addToArchive(tw, file, rel, entry)
	})
	if walkErr != nil {
		return nil, fmt.Errorf("harness: イメージ %s の組み立ての文脈を tar にできません: %w", spec.Name, walkErr)
	}
	if err := writeArchiveFile(tw, archiveDockerfile, dockerfile); err != nil {
		return nil, err
	}
	if err := tw.Close(); err != nil {
		return nil, fmt.Errorf("harness: イメージ %s の tar を閉じられません: %w", spec.Name, err)
	}
	return bytes.NewReader(buf.Bytes()), nil
}

// readDockerignore は、文脈のフォルダの .dockerignore を読む。ファイルが無ければ、何も除かない。
func readDockerignore(contextDir string) (*patternmatcher.PatternMatcher, error) {
	var patterns []string
	f, err := os.Open(filepath.Clean(filepath.Join(contextDir, ".dockerignore")))
	switch {
	case err == nil:
		defer func() { _ = f.Close() }()
		patterns, err = ignorefile.ReadAll(f)
		if err != nil {
			return nil, fmt.Errorf("harness: %s の .dockerignore を読めません: %w", contextDir, err)
		}
	case !errors.Is(err, fs.ErrNotExist):
		return nil, fmt.Errorf("harness: %s の .dockerignore を開けません: %w", contextDir, err)
	}
	matcher, err := patternmatcher.New(patterns)
	if err != nil {
		return nil, fmt.Errorf("harness: %s の .dockerignore の書き方が誤っています: %w", contextDir, err)
	}
	return matcher, nil
}

// addToArchive は、1つのファイルかフォルダかシンボリックリンクを tar に書く。
func addToArchive(tw *tar.Writer, file, rel string, entry fs.DirEntry) error {
	info, err := entry.Info()
	if err != nil {
		return err
	}
	link := ""
	if info.Mode()&fs.ModeSymlink != 0 {
		if link, err = os.Readlink(file); err != nil {
			return err
		}
	}
	header, err := tar.FileInfoHeader(info, link)
	if err != nil {
		return err
	}
	header.Name = rel
	if info.IsDir() {
		header.Name += "/"
	}
	if err := tw.WriteHeader(header); err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return nil
	}
	src, err := os.Open(filepath.Clean(file))
	if err != nil {
		return err
	}
	defer func() { _ = src.Close() }()
	_, err = io.Copy(tw, src)
	return err
}

// writeArchiveFile は、中身を指定したファイルを tar に書く。
func writeArchiveFile(tw *tar.Writer, name string, content []byte) error {
	header := &tar.Header{Name: name, Mode: 0o644, Size: int64(len(content)), Typeflag: tar.TypeReg}
	if err := tw.WriteHeader(header); err != nil {
		return fmt.Errorf("harness: %s を tar に書けません: %w", name, err)
	}
	if _, err := tw.Write(content); err != nil {
		return fmt.Errorf("harness: %s を tar に書けません: %w", name, err)
	}
	return nil
}

// Images は、組み立てたイメージの名前から、そのイメージの参照(リポジトリ:タグ)を引く表である。
type Images map[string]string

// BuildImages は、名前のイメージを、testcontainers-go がつなぐ Docker に組み立てさせる。
// 開発環境でホストの Docker が組み立てたイメージは dind から見えないので、毎回 Docker に組み立てさせる。
// タグには検査ごとの乱数を付け、同じ dind を使うほかの検査が組み立てたイメージと取り違えないようにする。
// 組み立ての記録は buildLog に書く。
func BuildImages(ctx context.Context, repoRoot string, buildLog io.Writer, names ...string) (Images, error) {
	provider, err := testcontainers.NewDockerProvider()
	if err != nil {
		return nil, fmt.Errorf("harness: Docker につなげません: %w", err)
	}
	defer func() { _ = provider.Close() }()

	tag := strings.ToLower(rand.Text())
	images := Images{}
	for _, name := range names {
		spec, err := FindImageSpec(name)
		if err != nil {
			return images, err
		}
		archive, err := BuildContextArchive(repoRoot, spec)
		if err != nil {
			return images, err
		}
		req := testcontainers.ContainerRequest{FromDockerfile: testcontainers.FromDockerfile{
			ContextArchive: archive,
			Dockerfile:     archiveDockerfile,
			Repo:           "keirekipro-compat-" + spec.Name,
			Tag:            tag,
			KeepImage:      true,
			BuildLogWriter: buildLog,
		}}
		ref, err := provider.BuildImage(ctx, &req)
		if err != nil {
			return images, fmt.Errorf("harness: イメージ %s を組み立てられません: %w", spec.Name, err)
		}
		images[spec.Name] = ref
	}
	return images, nil
}

// Remove は、組み立てたイメージのタグを消す。途中の層は消さずに残し、次の組み立てで使い回させる。
func (images Images) Remove(ctx context.Context) error {
	provider, err := testcontainers.NewDockerProvider()
	if err != nil {
		return fmt.Errorf("harness: Docker につなげません: %w", err)
	}
	defer func() { _ = provider.Close() }()

	var errs []error
	for _, ref := range images {
		if _, err := provider.Client().ImageRemove(ctx, ref, client.ImageRemoveOptions{PruneChildren: false}); err != nil {
			errs = append(errs, fmt.Errorf("harness: イメージ %s を消せません: %w", ref, err))
		}
	}
	return errors.Join(errs...)
}
