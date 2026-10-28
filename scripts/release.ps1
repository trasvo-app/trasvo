# Junta los instaladores ya compilados con nombres fijos (los enlaces de la web usan
# releases/latest/download/<nombre>) y escribe sus SHA-256.
#   npm run tauri build  (en desktop/)   y   flutter build apk --release  (en mobile/)
#   powershell -File scripts/release.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$version = (Get-Content "$root/desktop/src-tauri/tauri.conf.json" -Raw | ConvertFrom-Json).version
$out = "$root/release/$version"
New-Item -ItemType Directory -Force $out | Out-Null

$setup = Get-ChildItem "$root/desktop/src-tauri/target/release/bundle/nsis/Trasvo_${version}_x64-setup.exe"
Copy-Item $setup.FullName "$out/Trasvo-Setup-x64.exe" -Force
Copy-Item "$root/mobile/build/app/outputs/flutter-apk/app-release.apk" "$out/Trasvo.apk" -Force

$files = foreach ($name in 'Trasvo-Setup-x64.exe', 'Trasvo.apk') {
  $path = "$out/$name"
  [pscustomobject]@{
    name   = $name
    size   = (Get-Item $path).Length
    sha256 = (Get-FileHash $path -Algorithm SHA256).Hash.ToLower()
  }
}
($files | ForEach-Object { "$($_.sha256)  $($_.name)" }) -join "`n" | Set-Content "$out/SHA256SUMS.txt" -Encoding ascii -NoNewline

# La web muestra versión, tamaños y hashes desde aquí.
[ordered]@{ version = $version; date = (Get-Date -Format 'yyyy-MM-dd'); files = $files } |
  ConvertTo-Json -Depth 3 | Set-Content "$root/web/assets/release.json" -Encoding utf8

# Los hashes también van escritos en la guía, para que se vean sin JavaScript.
$guide = "$root/web/instalar.html"
$html = [IO.File]::ReadAllText($guide)
foreach ($f in $files) {
  $html = $html -replace "(data-hash=`"$([regex]::Escape($f.name))`">)[0-9a-f]*(</span>)", "`${1}$($f.sha256)`${2}"
}
[IO.File]::WriteAllText($guide, $html, (New-Object Text.UTF8Encoding $false))
Get-Content "$out/SHA256SUMS.txt"
