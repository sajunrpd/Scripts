# ---- CONFIGURATION ----
$clientID      = "<Your Client ID here>"
$clientSecret  = "<Your Client Secret here>"
$tenantID      = "<Your Tenant ID here>"
$outputPath    = "<Specify the output file path here>"


# Define list of compliant OS versions
$compliantVersions = @(
    "10.0.26100.4349","10.0.26100.4351","10.0.26100.4484", #24H2, June 10
    "10.0.22621.5472", "10.0.22631.5472","10.0.22631.5549","10.0.22621.5549", #23H2, June 10
    "10.0.19045.6036", #June 24 Patch, win10
    "10.0.19044.5965", "10.0.19045.5965", "10.0.19045.5968" #June10th Patch, Win10
    "15.5.0", "15.5", "14.7.6"
)

# ---- GET ACCESS TOKEN ----
$tokenEndpoint = "https://login.microsoftonline.com/$tenantID/oauth2/v2.0/token"
$body = @{
    client_id     = $clientID
    client_secret = $clientSecret
    scope         = "https://graph.microsoft.com/.default"
    grant_type    = "client_credentials"
}

try {
    $tokenResponse = Invoke-RestMethod -Uri $tokenEndpoint -Method POST -Body $body -ContentType "application/x-www-form-urlencoded"
    $accessToken = $tokenResponse.access_token
} catch {
    Write-Error "Failed to retrieve token: $_"
    exit
}

$headers = @{
    Authorization = "Bearer $accessToken"
    ContentType   = "application/json"
}

# ---- GET ALL MANAGED DEVICES (WITH PAGINATION) ----
$allDevices = @()
$uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices"

do {
    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET
        $allDevices += $response.value
        $uri = $response.'@odata.nextLink'
    } catch {
        Write-Error "Error retrieving devices: $_"
        break
    }
} while ($uri)

Write-Host "`nRetrieved $($allDevices.Count) devices from Intune.`n"

# ---- BUILD REPORT WITH ENROLLMENT DATE AS LAST COLUMN ----
$report = $allDevices | Select-Object `
    @{Name = "DeviceName"; Expression = { $_.deviceName }},
    @{Name = "OSVersion";  Expression = { $_.osVersion }},
    @{Name = "OSType";     Expression = { $_.operatingSystem }},
    @{Name = "Model";      Expression = { $_.model }},
    @{Name = "LastCheckInDateTime"; Expression = { $_.lastSyncDateTime }},
    @{Name = "OSFamily"; Expression = {
        $osType = $_.operatingSystem
        $osVer = $_.osVersion
        if ($osType -match "Windows") {
            try {
                if ([version]$osVer -ge [version]"10.0.22000.0") {
                    "Windows 11"
                } else {
                    "Windows 10"
                }
            } catch {
                "Windows (Unknown Version)"
            }
        } elseif ($osType -match "Mac") {
            "macOS"
        } elseif ($osType -match "Android") {
            "Android"
        } else {
            "Other"
        }
    }},
    @{Name = "ComplianceStatus"; Expression = {
        if ($compliantVersions -contains $_.osVersion) {
            "Compliant"
        } else {
            "Non-Compliant"
        }
    }},
    @{Name = "EnrollmentDateTime"; Expression = { $_.enrolledDateTime }}

# ---- EXPORT TO CSV ----
if (!(Test-Path -Path (Split-Path $outputPath))) {
    New-Item -Path (Split-Path $outputPath) -ItemType Directory | Out-Null
}
$report | Export-Csv -Path $outputPath -NoTypeInformation
Write-Host "✅ CSV exported to $outputPath`n"

# ---- SUMMARY ----
$totalCount       = $report.Count
$win10Devices     = $report | Where-Object { $_.OSFamily -eq "Windows 10" }
$win11Devices     = $report | Where-Object { $_.OSFamily -eq "Windows 11" }
$macDevices       = $report | Where-Object { $_.OSFamily -eq "macOS" }
$androidDevices   = $report | Where-Object { $_.OSFamily -eq "Android" }
$otherDevices     = $report | Where-Object { $_.OSFamily -eq "Other" -or $_.OSFamily -eq "Windows (Unknown Version)" }

$win10Compliant   = $win10Devices | Where-Object { $_.ComplianceStatus -eq "Compliant" }
$win11Compliant   = $win11Devices | Where-Object { $_.ComplianceStatus -eq "Compliant" }
$macCompliant     = $macDevices   | Where-Object { $_.ComplianceStatus -eq "Compliant" }
$androidCompliant = $androidDevices | Where-Object { $_.ComplianceStatus -eq "Compliant" }
$otherCompliant   = $otherDevices | Where-Object { $_.ComplianceStatus -eq "Compliant" }

$win10NonCompliant   = $win10Devices | Where-Object { $_.ComplianceStatus -eq "Non-Compliant" }
$win11NonCompliant   = $win11Devices | Where-Object { $_.ComplianceStatus -eq "Non-Compliant" }
$macNonCompliant     = $macDevices   | Where-Object { $_.ComplianceStatus -eq "Non-Compliant" }
$androidNonCompliant = $androidDevices | Where-Object { $_.ComplianceStatus -eq "Non-Compliant" }
$otherNonCompliant   = $otherDevices | Where-Object { $_.ComplianceStatus -eq "Non-Compliant" }

# ---- OUTPUT STATS TO CONSOLE ----
Write-Host "---------- Device Compliance Summary ----------"
Write-Host "Total Devices:             $totalCount"
Write-Host "`nWindows 10 Devices:        $($win10Devices.Count) (Compliant: $($win10Compliant.Count), Non-Compliant: $($win10NonCompliant.Count))"
Write-Host "Windows 11 Devices:        $($win11Devices.Count) (Compliant: $($win11Compliant.Count), Non-Compliant: $($win11NonCompliant.Count))"
Write-Host "macOS Devices:             $($macDevices.Count) (Compliant: $($macCompliant.Count), Non-Compliant: $($macNonCompliant.Count))"
Write-Host "Android Devices:           $($androidDevices.Count) (Compliant: $($androidCompliant.Count), Non-Compliant: $($androidNonCompliant.Count))"
Write-Host "Other OS Devices:          $($otherDevices.Count) (Compliant: $($otherCompliant.Count), Non-Compliant: $($otherNonCompliant.Count))"
Write-Host "-----------------------------------------------`n"

