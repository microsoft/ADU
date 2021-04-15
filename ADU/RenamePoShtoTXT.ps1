$path = (Get-Location).Path

$Files = Get-ChildItem -Path $path -Recurse -Include "*.ps1" -Force

foreach ($file in $files) {
    $NewName = $file.name -replace ".ps1", "~ps.txt"
    Rename-Item -Path $file.FullName -NewName $NewName
  }

$Files = Get-ChildItem -Path $path -Recurse -Include "*.bat" -Force

foreach ($file in $files) {
    $NewName = $file.name -replace ".bat", "~bat.txt"
    Rename-Item -Path $file.FullName -NewName $NewName
  }


$Files = Get-ChildItem -Path $path -Recurse -Include "*.ps1" -Hidden

foreach ($file in $files) {
    $NewName = $file.name -replace ".ps1", "~ps.txt"
    Rename-Item -Path $file.FullName -NewName $NewName
  }

$Files = Get-ChildItem -Path $path -Recurse -Include "*.bat" -Hidden

foreach ($file in $files) {
    $NewName = $file.name -replace ".bat", "~bat.txt"
    Rename-Item -Path $file.FullName -NewName $NewName
  }