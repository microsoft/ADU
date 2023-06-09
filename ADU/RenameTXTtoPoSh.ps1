function Rename-Files {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Directory,

        [Parameter(Mandatory=$true)]
        [string[]]$Extensions
    )

    $Files = Get-ChildItem -Path $Directory -Recurse -Include "*~*.txt" -Force

    foreach ($file in $Files) {
        $extension = $file.Extension.TrimStart('.')
        if ($Extensions -contains $extension) {
            $NewName = $file.Name -replace "~$extension.txt", ".$extension"
            Rename-Item -Path $file.FullName -NewName $NewName
        }
    }

    Write-Host "File renaming completed."
}

# Usage example
$Directory = (Get-Location).Path
$Extensions = @("ps", "bat")

Rename-Files -Directory $Directory -Extensions $Extensions
