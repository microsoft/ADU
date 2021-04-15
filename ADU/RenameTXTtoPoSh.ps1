$path = (Get-Location).Path

$Files = Get-ChildItem -Path $path -Recurse -Include "*~ps.txt" -Force

foreach ($file in $files) {
    $NewName = $file.name -replace "~ps.txt", ".ps1"
    Rename-Item -Path $file.FullName -NewName $NewName
  }

$Files = Get-ChildItem -Path $path -Recurse -Include "*~bat.txt" -Force

foreach ($file in $files) {
    $NewName = $file.name -replace "~bat.txt", ".bat"
    Rename-Item -Path $file.FullName -NewName $NewName
  }

$Files = Get-ChildItem -Path $path -Recurse -Include "*~ps.txt" -Hidden

foreach ($file in $files) {
    $NewName = $file.name -replace "~ps.txt", ".ps1"
    Rename-Item -Path $file.FullName -NewName $NewName
  }

$Files = Get-ChildItem -Path $path -Recurse -Include "*~bat.txt" -Hidden

foreach ($file in $files) {
    $NewName = $file.name -replace "~bat.txt", ".bat"
    Rename-Item -Path $file.FullName -NewName $NewName
  }

