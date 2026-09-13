$paths = @(
  'D:\workspace\git-code\ledgerly\apps\client\lib',
  'D:\workspace\git-code\ledgerly\apps\client\test',
  'D:\workspace\git-code\ledgerly\apps\client\integration_test',
  'D:\workspace\git-code\ledgerly\packages',
  'D:\workspace\git-code\ledgerly\server\src',
  'D:\workspace\git-code\ledgerly\server\tests',
  'D:\workspace\git-code\ledgerly\server\crates'
)
foreach ($p in $paths) {
  $files = Get-ChildItem -Path $p -Recurse -Include *.dart,*.rs -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notlike '*.g.dart' }
  $total = 0
  foreach ($f in $files) {
    $lines = (Get-Content $f.FullName -Raw).Split("`n").Count
    $total += $lines
  }
  Write-Host "$p : $total lines ($($files.Count) files)"
}
