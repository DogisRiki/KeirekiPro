// 画面の URL を SPA の入口(/index.html)に書き換える。
// 最後の区切りに "." を含む URL(/assets/*.js、/favicon.ico など)は、ファイルとしてそのまま S3 に取りに行く。
// この関数は既定の経路だけに付けるので、/api/* と /media/* には働かない。
function handler(event) {
  var request = event.request;
  var uri = request.uri;
  var lastSegment = uri.substring(uri.lastIndexOf("/") + 1);

  if (lastSegment.indexOf(".") === -1) {
    request.uri = "/index.html";
  }

  return request;
}
