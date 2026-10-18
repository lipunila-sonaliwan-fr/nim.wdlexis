# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdlexis+ : installe Zig 0.17.0 (officiel, ziglang.org) pour un hôte Windows
# dans winZG\<arch>\zig.exe (+ winZG\lib), avec contrôle SHA-256.
#
#   powershell -ExecutionPolicy Bypass -File outils\preparer_zig.ps1 [x86_64|aarch64]
param([string]$Arch = "")
$ErrorActionPreference = "Stop"
$Version = "0.17.0"
$Here = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if ($Arch -eq "") {
  if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { $Arch = "aarch64" } else { $Arch = "x86_64" }
}
$Sums = @{
  "x86_64"  = "b5663f69581dcf391293fbf16c06cb80d81d806545ce618b4d0bab7f0eb8c428";
  "aarch64" = "0a59d91fa1cb40cf068e9b0954434ce973500c7a2ea749f1e01af62cdab52d26"
}
if (-not $Sums.ContainsKey($Arch)) { throw "architecture inconnue : $Arch" }
$Name = "zig-$Arch-windows-$Version"
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wdlexis-zig-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $Tmp | Out-Null
try {
  $Zip = Join-Path $Tmp "$Name.zip"
  $Url = "https://ziglang.org/download/$Version/$Name.zip"
  Write-Host "Téléchargement : $Url"
  Invoke-WebRequest -Uri $Url -OutFile $Zip
  $Got = (Get-FileHash -Algorithm SHA256 $Zip).Hash.ToLower()
  if ($Got -ne $Sums[$Arch]) { throw "empreinte SHA-256 incorrecte : $Got" }
  Write-Host "Empreinte SHA-256 vérifiée."
  Expand-Archive -Path $Zip -DestinationPath $Tmp
  $Dest = Join-Path $Here "winZG"
  New-Item -ItemType Directory -Force -Path (Join-Path $Dest $Arch) | Out-Null
  Copy-Item (Join-Path $Tmp "$Name\zig.exe") (Join-Path $Dest "$Arch\zig.exe") -Force
  Copy-Item (Join-Path $Tmp "$Name\LICENSE") (Join-Path $Dest "LICENSE") -Force
  if (-not (Test-Path (Join-Path $Dest "lib\std\std.zig"))) {
    Copy-Item (Join-Path $Tmp "$Name\lib") (Join-Path $Dest "lib") -Recurse -Force
  }
  Write-Host "Zig $Version installé : winZG\$Arch\zig.exe"
} finally {
  Remove-Item -Recurse -Force $Tmp
}
