#Script Created on 7th August 2025, by sajunrpd@gmail.com
 
#Get the currently logged-in user's session (interactive session)
$loggedInUser = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty UserName

if (-not $loggedInUser) {
    Write-Host "No user is currently logged in. Cannot assign permissions."
    exit 1
}

# Extract domain and username
if ($loggedInUser -like "*\\*") {
    $userParts = $loggedInUser -split "\\"
    $usernameOnly = $userParts[1]
} else {
    $usernameOnly = $loggedInUser
}

# Search for the actual UPN/email in the profile list (offline safe)
$profile = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\IdentityStore\LogonCache" -Recurse |
    Where-Object { $_.GetValue("UserDisplayName") -like "*$usernameOnly*" } |
    Select-Object -First 1

if ($profile) {
    $upn = $profile.GetValue("UserDisplayName")
} else {
    $upn = $loggedInUser  # fallback
}

Write-Host "Using UPN: $upn"

# Define folders
$folders = @("C:\Oracle_32", "C:\Oracle_64")

foreach ($folderPath in $folders) {
    if (-Not (Test-Path -Path $folderPath)) {
        New-Item -Path $folderPath -ItemType Directory -Force | Out-Null
        Write-Host "Created: $folderPath"
    } else {
        Write-Host "Exists: $folderPath"
    }

    $acl = Get-Acl -Path $folderPath

    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $upn,
        "FullControl",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )

    $acl.SetAccessRule($accessRule)
    Set-Acl -Path $folderPath -AclObject $acl

    Write-Host "Granted Full Control to $upn on $folderPath"
}

