#script to check server details and KB information from CSV file

param(
    [Parameter(Mandatory=$true, HelpMessage="Path to the CSV file containing server names")]
    [string]$csvFilePath,
    
    [Parameter(Mandatory=$false, HelpMessage="Output results to CSV file")]
    [string]$outputCsvPath
)

# Validate CSV file exists
if (-not (Test-Path -Path $csvFilePath)) {
    Write-Error "CSV file not found at path: $csvFilePath"
    exit 1
}

# Import the CSV file
try {
    $servers = Import-Csv -Path $csvFilePath
    Write-Host "Successfully imported $($servers.Count) server(s) from CSV file" -ForegroundColor Green
}
catch {
    Write-Error "Failed to import CSV file: $_"
    exit 1
}

# Initialize results array
$results = @()

# Function to get server KB details and uptime
function Get-ServerKBDetails {
    param(
        [string]$serverName,
        [string]$credential
    )
    
    try {
        $serverInfo = @{
            ServerName = $serverName
            Status = "Offline"
            Uptime = "N/A"
            UptimeDays = 0
            LastBootTime = "N/A"
            InstalledKBs = "N/A"
            KBCount = 0
            Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            Error = ""
        }
        
        # Test connectivity
        if (Test-Connection -ComputerName $serverName -Count 1 -Quiet) {
            $serverInfo.Status = "Online"
            
            # Get last boot time and uptime
            try {
                $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $serverName -ErrorAction Stop
                $bootTime = $osInfo.LastBootUpTime
                $currentTime = Get-Date
                $uptime = $currentTime - $bootTime
                
                $serverInfo.LastBootTime = $bootTime.ToString("yyyy-MM-dd HH:mm:ss")
                $serverInfo.Uptime = "{0} days, {1} hours, {2} minutes" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
                $serverInfo.UptimeDays = $uptime.Days
            }
            catch {
                $serverInfo.Error += "Failed to get boot time: $_ | "
            }
            
            # Get installed KB articles
            try {
                $kbArticles = Get-HotFix -ComputerName $serverName -ErrorAction Stop | Select-Object -ExpandProperty HotFixID
                $serverInfo.KBCount = $kbArticles.Count
                $serverInfo.InstalledKBs = ($kbArticles -join "; ")
            }
            catch {
                $serverInfo.Error += "Failed to get KB articles: $_ | "
            }
        }
        else {
            $serverInfo.Status = "Offline"
            $serverInfo.Error = "Server is not reachable"
        }
        
        return $serverInfo
    }
    catch {
        return @{
            ServerName = $serverName
            Status = "Error"
            Error = $_.Exception.Message
            Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        }
    }
}

# Process each server from CSV
Write-Host "`nProcessing servers..." -ForegroundColor Cyan
foreach ($server in $servers) {
    $serverName = $server.ServerName -or $server.Name -or $server.ComputerName
    
    if ([string]::IsNullOrEmpty($serverName)) {
        Write-Warning "Skipping row with no server name"
        continue
    }
    
    Write-Host "Checking server: $serverName" -ForegroundColor Yellow
    $serverDetails = Get-ServerKBDetails -serverName $serverName
    $results += $serverDetails
}

# Display results in console
Write-Host "`n=== SERVER KB DETAILS AND UPTIME REPORT ===" -ForegroundColor Cyan
Write-Host ""

$results | Format-Table -AutoSize -Property @(
    'Timestamp',
    'ServerName',
    'Status',
    'Uptime',
    'UptimeDays',
    'LastBootTime',
    'KBCount',
    @{Label='HasErrors'; Expression={if($_.Error) {'Yes'} else {'No'}}}
) -Wrap

# Export to CSV if output path is specified
if (-not [string]::IsNullOrEmpty($outputCsvPath)) {
    try {
        $results | Export-Csv -Path $outputCsvPath -NoTypeInformation -Force
        Write-Host "`nResults exported to: $outputCsvPath" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to export results to CSV: $_"
    }
}

# Display summary
Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Total Servers Processed: $($results.Count)"
Write-Host "Online Servers: $($results | Where-Object { $_.Status -eq 'Online' } | Measure-Object).Count"
Write-Host "Offline Servers: $($results | Where-Object { $_.Status -eq 'Offline' } | Measure-Object).Count"
Write-Host "Total KB Articles Found: $($results | Measure-Object -Property KBCount -Sum | Select-Object -ExpandProperty Sum)"

# Return results
return $results
