# 画像の検査のテストの見本

`small.jpg` と `small.gif` は、Claude が 2026-11-13 に Java の `ImageIO.write` で書いた、横 2 画素、縦 2 画素の画像である。左上の1画素だけが赤い。

`image_test.go` は、JPEG と GIF の画像を、`image/jpeg` と `image/gif` で作らずに、この見本のファイルから読む。テストがこれらを読み込むと、`image.go` が画像の形式を読み込み忘れても、テストが通ってしまうためである。
