// =====================================================================
// windows-launcher.cs — Windows の予定が動かす、窓を持たない起動用のプログラム
//
// memory-inspect.sh の enable が、このソースから、点検の状態の場所に windows-launcher.exe を作る
// (Add-Type -OutputType WindowsApplication)。窓を持たない種類のプログラムなので、予定から動いても窓が出ない。
//
// 使い方: windows-launcher.exe <プログラム> [<引数>...]
// 1つ目の引数のプログラムを、残りの引数を付けて、窓を作らずに起動し、終わるのを待ち、そのプログラムの終了コードで終わる。
// 引数が無いときは 2 で、プログラムを起動できなかったときは 3 で終わる
// =====================================================================
using System;
using System.Diagnostics;
using System.Text;

static class Launcher
{
    static int Main(string[] args)
    {
        if (args.Length < 1) return 2;
        var si = new ProcessStartInfo(args[0]);
        si.UseShellExecute = false;
        si.CreateNoWindow = true;
        // ProcessStartInfo は引数を1つの文字列で受けるので、引数ごとに囲んでから空白でつなぐ
        var sb = new StringBuilder();
        for (int i = 1; i < args.Length; i++)
        {
            if (i > 1) sb.Append(' ');
            sb.Append(Quote(args[i]));
        }
        si.Arguments = sb.ToString();
        try
        {
            using (var p = Process.Start(si))
            {
                p.WaitForExit();
                return p.ExitCode;
            }
        }
        catch (Exception)
        {
            return 3;
        }
    }

    // 空白か二重引用符を含む引数と空の引数を、Windows のコマンドラインの決まりのとおりに二重引用符で囲む。
    // 二重引用符の前の逆斜線と、囲みの終わりの前の逆斜線は数を倍にし、中の二重引用符は前に逆斜線を置いてエスケープする
    static string Quote(string a)
    {
        if (a.Length > 0 && a.IndexOfAny(new[] { ' ', '\t', '"' }) < 0) return a;
        var sb = new StringBuilder("\"");
        int bs = 0;
        foreach (char c in a)
        {
            if (c == '\\') { bs++; continue; }
            if (c == '"') { sb.Append('\\', bs * 2 + 1); sb.Append('"'); }
            else { sb.Append('\\', bs); sb.Append(c); }
            bs = 0;
        }
        sb.Append('\\', bs * 2);
        sb.Append('"');
        return sb.ToString();
    }
}
