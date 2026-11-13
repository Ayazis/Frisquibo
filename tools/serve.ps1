# Minimal static file server for the Godot web export (no Python/Node needed).
# Usage: powershell -ExecutionPolicy Bypass -File tools/serve.ps1 [-Port 8060] [-Root web]
param([int]$Port = 8060, [string]$Root = "web")

$root = (Resolve-Path (Join-Path $PSScriptRoot "..\$Root")).Path
$types = @{
    ".html" = "text/html"; ".js" = "application/javascript"; ".wasm" = "application/wasm"
    ".pck" = "application/octet-stream"; ".png" = "image/png"; ".json" = "application/json"
}
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Serving $root at http://localhost:$Port/"
while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $path = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart("/"))
    if ($path -eq "") { $path = "index.html" }
    $file = [System.IO.Path]::GetFullPath((Join-Path $root $path))
    $res = $ctx.Response
    $res.Headers.Add("Cross-Origin-Opener-Policy", "same-origin")
    $res.Headers.Add("Cross-Origin-Embedder-Policy", "require-corp")
    $res.Headers.Add("Cache-Control", "no-store")
    if ($file.StartsWith($root) -and (Test-Path $file -PathType Leaf)) {
        $ext = [System.IO.Path]::GetExtension($file).ToLower()
        $res.ContentType = if ($types.ContainsKey($ext)) { $types[$ext] } else { "application/octet-stream" }
        $bytes = [System.IO.File]::ReadAllBytes($file)
        $res.ContentLength64 = $bytes.Length
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
        Write-Host "200 /$path"
    } else {
        $res.StatusCode = 404
        Write-Host "404 /$path"
    }
    $res.Close()
}
