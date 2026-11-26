# Install madal on Windows from the latest GitHub release.
#
#   irm https://madal.facets.cloud/install.ps1 | iex
#
# It downloads madal_<version>_windows_amd64.zip, checks its SHA-256 against the release's
# checksums.txt, and installs madal.exe into $env:MADAL_INSTALL_DIR (default
# %LOCALAPPDATA%\Programs\madal, where Windows apps install for one user without admin rights).
# It adds that folder to your user Path when it isn't there yet. Set $env:MADAL_VERSION =
# 'v0.1.1' to pin a version.
#
#   $env:MADAL_ALL = '1'; irm https://madal.facets.cloud/install.ps1 | iex
#
# also installs the agent skill (madal skills install, into each agent found under your home).
# A saved copy takes the same as a switch: .\install.ps1 -All. The madal Meetings app is Mac
# only, so on Windows there is no app to install.
#
# It needs no admin rights and leaves the execution policy alone.
param([switch]$All)

& {
  param([bool]$all)
  $ErrorActionPreference = 'Stop'
  # Windows PowerShell 5.1 draws a progress bar that makes downloads many times slower.
  $ProgressPreference = 'SilentlyContinue'
  # Windows PowerShell 5.1 may not offer TLS 1.2 by default, and GitHub requires it.
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

  $repo = 'Facets-cloud/madal-releases'
  function fail($msg) { throw "madal install: $msg" }

  if ([Environment]::OSVersion.Platform -ne 'Win32NT') {
    fail 'install.ps1 is for Windows; on macOS or Linux run: curl -fsSL https://madal.facets.cloud/install.sh | sh'
  }
  if (-not [Environment]::Is64BitOperatingSystem) { fail 'madal needs 64-bit Windows' }
  # Only an x64 build is published. Windows 11 on Arm runs it under emulation.
  $cpu = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
  if ($cpu -eq 'ARM64') { Write-Host 'No Arm build of madal for Windows yet; installing the x64 one, which Windows 11 runs under emulation.' }

  $dir = if ($env:MADAL_INSTALL_DIR) { $env:MADAL_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'Programs\madal' }

  $version = $env:MADAL_VERSION
  if (-not $version) {
    # releases/latest redirects to .../releases/tag/<version>. Reading the redirect avoids the
    # GitHub API, which turns away unauthenticated callers past 60 requests an hour.
    try {
      $req = [Net.WebRequest]::Create("https://github.com/$repo/releases/latest")
      $req.Method = 'HEAD'
      $req.AllowAutoRedirect = $false
      $resp = $req.GetResponse()
      $location = $resp.Headers['Location']
      $resp.Close()
      if ($location -match '/releases/tag/([^/?#]+)$') { $version = $Matches[1] }
    } catch {}
    if (-not $version) {
      try { $version = (Invoke-RestMethod -UseBasicParsing "https://api.github.com/repos/$repo/releases/latest").tag_name } catch {}
    }
    if (-not $version) { fail "couldn't find the latest release" }
  }

  $base = "https://github.com/$repo/releases/download/$version"
  $name = "madal_$($version.TrimStart('v'))_windows_amd64"
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ("madal-" + [guid]::NewGuid())
  New-Item -ItemType Directory -Path $tmp | Out-Null
  try {
    Write-Host "Downloading madal $version for windows/amd64"
    try { Invoke-WebRequest -UseBasicParsing -Uri "$base/$name.zip" -OutFile "$tmp\$name.zip" }
    catch { fail "couldn't download $base/$name.zip ($($_.Exception.Message))" }
    Write-Host 'Downloading checksums'
    Invoke-WebRequest -UseBasicParsing -Uri "$base/checksums.txt" -OutFile "$tmp\checksums.txt"

    $want = $null
    foreach ($line in Get-Content "$tmp\checksums.txt") {
      $f = -split $line
      if ($f.Count -eq 2 -and $f[1] -eq "$name.zip") { $want = $f[0] }
    }
    if (-not $want) { fail "no checksum listed for $name.zip" }
    # -ne compares strings case-insensitively; Get-FileHash prints upper case.
    if ((Get-FileHash -Algorithm SHA256 "$tmp\$name.zip").Hash -ne $want) { fail "checksum mismatch for $name.zip; not installing" }
    Write-Host 'Checksum verified'

    Expand-Archive -Path "$tmp\$name.zip" -DestinationPath $tmp
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $exe = Join-Path $dir 'madal.exe'
    try { Copy-Item -Force "$tmp\$name\madal.exe" $exe }
    catch { fail "couldn't write $exe; if madal is running, stop it and run this again ($($_.Exception.Message))" }
    Write-Host "Installed $exe"
  } finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }

  # Add the folder to the user Path (no admin needed) unless it's already there. New terminals
  # pick it up; this one gets it too, so the next command works here.
  $norm = { param($p) $p.Trim().TrimEnd('\') }
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  $entries = @(if ($userPath) { $userPath -split ';' | Where-Object { $_ } })
  if (-not ($entries | Where-Object { (& $norm $_) -eq (& $norm $dir) })) {
    [Environment]::SetEnvironmentVariable('Path', (@($entries) + $dir) -join ';', 'User')
    Write-Host "Added $dir to your user Path"
  }
  if (-not (($env:Path -split ';') | Where-Object { $_ -and (& $norm $_) -eq (& $norm $dir) })) {
    $env:Path = "$dir;$env:Path"
  }

  if ($all) {
    # The binary carries the skill; this writes it into each agent's skills folder.
    & $exe skills install
    if ($LASTEXITCODE -ne 0) { fail "madal skills install failed" }
    Write-Host 'Skipping the madal app: it needs a Mac with Apple Silicon'
  }
  Write-Host 'Next: madal login'
} ($All -or $env:MADAL_ALL -eq '1')
