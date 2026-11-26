<#
.SYNOPSIS
    Configures or restores Windows system DNS over HTTPS (DoH) using Cloudflare.
.DESCRIPTION
    Invoked by the DPI Proxy Windows MSI installer during install, upgrade,
    rollback, and uninstall. Configures Cloudflare DNS (1.1.1.1 / 1.0.0.1, plus
    IPv6 when an IPv6 default route is present) with Windows native DoH enabled
    on physical network adapters, while backing up and restoring prior settings.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Install', 'Uninstall')]
    [string]$Action
)

Set-StrictMode -Version Latest

$CloudflareDohTemplate = 'https://cloudflare-dns.com/dns-query'
$CloudflareIPv4 = @('1.1.1.1', '1.0.0.1')
$CloudflareIPv6 = @('2606:4700:4700::1111', '2606:4700:4700::1001')
$BackupRootSubKey = 'Software\Delnegend\DpiProxy\DnsBackup'
# DNS_DOH_SERVER_SETTINGS_ENABLE_AUTO (0x0001): use automatic template, encrypted only.
$DohFlagsAutoEncrypted = [long]1

function Test-RegistrySubKey {
    param([Parameter(Mandatory = $true)][string]$SubKeyPath)
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($SubKeyPath, $false)
    if ($null -ne $key) {
        $key.Dispose()
        return $true
    }
    return $false
}

function Get-RegistryValue {
    param(
        [Parameter(Mandatory = $true)][string]$SubKeyPath,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($SubKeyPath, $false)
    if ($null -eq $key) {
        return $null
    }
    try {
        return $key.GetValue($Name, $null)
    }
    finally {
        $key.Dispose()
    }
}

function Set-RegistryValue {
    param(
        [Parameter(Mandatory = $true)][string]$SubKeyPath,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][Microsoft.Win32.RegistryValueKind]$Kind
    )
    $key = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($SubKeyPath)
    if ($null -eq $key) {
        throw "Failed to create or open HKLM\$SubKeyPath"
    }
    try {
        $key.SetValue($Name, $Value, $Kind)
    }
    finally {
        $key.Dispose()
    }
}

function Remove-RegistrySubKeyTree {
    param([Parameter(Mandatory = $true)][string]$SubKeyPath)
    if (Test-RegistrySubKey -SubKeyPath $SubKeyPath) {
        [Microsoft.Win32.Registry]::LocalMachine.DeleteSubKeyTree($SubKeyPath, $false)
    }
}

function Get-RegistrySubKeyNames {
    param([Parameter(Mandatory = $true)][string]$SubKeyPath)
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($SubKeyPath, $false)
    if ($null -eq $key) {
        return @()
    }
    try {
        return @($key.GetSubKeyNames())
    }
    finally {
        $key.Dispose()
    }
}

function Split-NameServerList {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }
    return @($Value -split '[,;\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Test-NativeDohSupported {
    return (
        $null -ne (Get-Command -Name 'Get-DnsClientDohServerAddress' -ErrorAction SilentlyContinue) -and
        $null -ne (Get-Command -Name 'Add-DnsClientDohServerAddress' -ErrorAction SilentlyContinue) -and
        $null -ne (Get-Command -Name 'Set-DnsClientDohServerAddress' -ErrorAction SilentlyContinue)
    )
}

function Enable-GlobalCloudflareDoh {
    if (-not (Test-NativeDohSupported)) {
        return
    }

    foreach ($ip in @($CloudflareIPv4 + $CloudflareIPv6)) {
        try {
            $backupKey = "$BackupRootSubKey\GlobalDoh\$ip"
            $existing = Get-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue | Select-Object -First 1

            if (-not (Test-RegistrySubKey -SubKeyPath $backupKey)) {
                if ($null -ne $existing) {
                    Set-RegistryValue -SubKeyPath $backupKey -Name 'Existed' -Value 1 -Kind ([Microsoft.Win32.RegistryValueKind]::DWord)
                    Set-RegistryValue -SubKeyPath $backupKey -Name 'DohTemplate' -Value ([string]$existing.DohTemplate) -Kind ([Microsoft.Win32.RegistryValueKind]::String)
                    Set-RegistryValue -SubKeyPath $backupKey -Name 'AutoUpgrade' -Value ([int][bool]$existing.AutoUpgrade) -Kind ([Microsoft.Win32.RegistryValueKind]::DWord)
                    Set-RegistryValue -SubKeyPath $backupKey -Name 'AllowFallbackToUdp' -Value ([int][bool]$existing.AllowFallbackToUdp) -Kind ([Microsoft.Win32.RegistryValueKind]::DWord)
                }
                else {
                    Set-RegistryValue -SubKeyPath $backupKey -Name 'Existed' -Value 0 -Kind ([Microsoft.Win32.RegistryValueKind]::DWord)
                }
            }

            if ($null -ne $existing) {
                Set-DnsClientDohServerAddress `
                    -ServerAddress $ip `
                    -DohTemplate $CloudflareDohTemplate `
                    -AllowFallbackToUdp $false `
                    -AutoUpgrade $true `
                    -ErrorAction Stop
            }
            else {
                Add-DnsClientDohServerAddress `
                    -ServerAddress $ip `
                    -DohTemplate $CloudflareDohTemplate `
                    -AllowFallbackToUdp $false `
                    -AutoUpgrade $true `
                    -ErrorAction Stop
            }
        }
        catch {
            Write-Warning "Failed to configure global DoH entry for ${ip}: $_"
        }
    }
}

function Restore-GlobalCloudflareDoh {
    if (-not (Test-NativeDohSupported)) {
        return
    }

    $globalBackupRoot = "$BackupRootSubKey\GlobalDoh"
    foreach ($ip in @(Get-RegistrySubKeyNames -SubKeyPath $globalBackupRoot)) {
        try {
            $backupKey = "$globalBackupRoot\$ip"
            $existed = Get-RegistryValue -SubKeyPath $backupKey -Name 'Existed'
            if ($existed -eq 1) {
                $template = [string](Get-RegistryValue -SubKeyPath $backupKey -Name 'DohTemplate')
                $autoUpgrade = [bool](Get-RegistryValue -SubKeyPath $backupKey -Name 'AutoUpgrade')
                $allowFallback = [bool](Get-RegistryValue -SubKeyPath $backupKey -Name 'AllowFallbackToUdp')

                if (-not [string]::IsNullOrWhiteSpace($template)) {
                    Set-DnsClientDohServerAddress `
                        -ServerAddress $ip `
                        -DohTemplate $template `
                        -AllowFallbackToUdp $allowFallback `
                        -AutoUpgrade $autoUpgrade `
                        -ErrorAction SilentlyContinue
                }
            }
            elseif ($existed -eq 0) {
                if ($null -ne (Get-Command -Name 'Remove-DnsClientDohServerAddress' -ErrorAction SilentlyContinue)) {
                    Remove-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue
                }
            }
        }
        catch {
            Write-Warning "Failed to restore global DoH entry for ${ip}: $_"
        }
    }
}

function Get-TargetAdapters {
    return @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object {
        $_.Status -ne 'Disabled' -and
        $_.InterfaceDescription -notmatch 'Bluetooth' -and
        $_.PhysicalMediaType -ne 'Bluetooth' -and
        -not [string]::IsNullOrWhiteSpace($_.InterfaceGuid)
    })
}

function Install-CloudflareDns {
    $dohSupported = Test-NativeDohSupported
    Enable-GlobalCloudflareDoh

    foreach ($adapter in @(Get-TargetAdapters)) {
        try {
            $guid = $adapter.InterfaceGuid
            $ifIndex = $adapter.ifIndex
            $hasIPv4 = $null -ne (Get-NetIPInterface -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
            $hasIPv6Route = $null -ne (Get-NetRoute -InterfaceIndex $ifIndex -AddressFamily IPv6 -DestinationPrefix '::/0' -ErrorAction SilentlyContinue)

            if (-not $hasIPv4 -and -not $hasIPv6Route) {
                continue
            }

            $adapterBackupKey = "$BackupRootSubKey\Adapters\$guid"
            $dohRoot = "SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$guid\DohInterfaceSettings"

            if (-not (Test-RegistrySubKey -SubKeyPath $adapterBackupKey)) {
                $origV4 = [string](Get-RegistryValue -SubKeyPath "SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid" -Name 'NameServer')
                $origV6 = [string](Get-RegistryValue -SubKeyPath "SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$guid" -Name 'NameServer')

                $dohV4Added = @()
                if ($hasIPv4 -and $dohSupported) {
                    foreach ($ip in $CloudflareIPv4) {
                        if (-not (Test-RegistrySubKey -SubKeyPath "$dohRoot\Doh\$ip")) {
                            $dohV4Added += $ip
                        }
                    }
                }

                $dohV6Added = @()
                if ($hasIPv6Route -and $dohSupported) {
                    foreach ($ip in $CloudflareIPv6) {
                        if (-not (Test-RegistrySubKey -SubKeyPath "$dohRoot\Doh6\$ip")) {
                            $dohV6Added += $ip
                        }
                    }
                }

                Set-RegistryValue -SubKeyPath $adapterBackupKey -Name 'IPv4NameServer' -Value $origV4 -Kind ([Microsoft.Win32.RegistryValueKind]::String)
                Set-RegistryValue -SubKeyPath $adapterBackupKey -Name 'IPv6NameServer' -Value $origV6 -Kind ([Microsoft.Win32.RegistryValueKind]::String)
                Set-RegistryValue -SubKeyPath $adapterBackupKey -Name 'IPv4Configured' -Value ([int]$hasIPv4) -Kind ([Microsoft.Win32.RegistryValueKind]::DWord)
                Set-RegistryValue -SubKeyPath $adapterBackupKey -Name 'IPv6Configured' -Value ([int]$hasIPv6Route) -Kind ([Microsoft.Win32.RegistryValueKind]::DWord)
                Set-RegistryValue -SubKeyPath $adapterBackupKey -Name 'DohIPv4Added' -Value ($dohV4Added -join ',') -Kind ([Microsoft.Win32.RegistryValueKind]::String)
                Set-RegistryValue -SubKeyPath $adapterBackupKey -Name 'DohIPv6Added' -Value ($dohV6Added -join ',') -Kind ([Microsoft.Win32.RegistryValueKind]::String)
            }
            elseif ($hasIPv6Route -and (Get-RegistryValue -SubKeyPath $adapterBackupKey -Name 'IPv6Configured') -ne 1) {
                $dohV6Added = @()
                if ($dohSupported) {
                    foreach ($ip in $CloudflareIPv6) {
                        if (-not (Test-RegistrySubKey -SubKeyPath "$dohRoot\Doh6\$ip")) {
                            $dohV6Added += $ip
                        }
                    }
                }
                Set-RegistryValue -SubKeyPath $adapterBackupKey -Name 'IPv6Configured' -Value 1 -Kind ([Microsoft.Win32.RegistryValueKind]::DWord)
                Set-RegistryValue -SubKeyPath $adapterBackupKey -Name 'DohIPv6Added' -Value ($dohV6Added -join ',') -Kind ([Microsoft.Win32.RegistryValueKind]::String)
            }

            if ($hasIPv4) {
                if ($dohSupported) {
                    foreach ($ip in $CloudflareIPv4) {
                        Set-RegistryValue -SubKeyPath "$dohRoot\Doh\$ip" -Name 'DohFlags' -Value $DohFlagsAutoEncrypted -Kind ([Microsoft.Win32.RegistryValueKind]::QWord)
                    }
                }
                Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses $CloudflareIPv4 -ErrorAction Stop
            }

            if ($hasIPv6Route) {
                if ($dohSupported) {
                    foreach ($ip in $CloudflareIPv6) {
                        Set-RegistryValue -SubKeyPath "$dohRoot\Doh6\$ip" -Name 'DohFlags' -Value $DohFlagsAutoEncrypted -Kind ([Microsoft.Win32.RegistryValueKind]::QWord)
                    }
                }
                Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses $CloudflareIPv6 -ErrorAction Stop
            }
        }
        catch {
            Write-Warning "Failed to configure DNS on adapter $($adapter.Name): $_"
        }
    }

    Clear-DnsClientCache -ErrorAction SilentlyContinue
}

function Uninstall-CloudflareDns {
    $adaptersBackupRoot = "$BackupRootSubKey\Adapters"
    $allAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue)

    foreach ($guid in @(Get-RegistrySubKeyNames -SubKeyPath $adaptersBackupRoot)) {
        try {
            $adapterBackupKey = "$adaptersBackupRoot\$guid"
            $origV4 = [string](Get-RegistryValue -SubKeyPath $adapterBackupKey -Name 'IPv4NameServer')
            $origV6 = [string](Get-RegistryValue -SubKeyPath $adapterBackupKey -Name 'IPv6NameServer')
            $v4Configured = (Get-RegistryValue -SubKeyPath $adapterBackupKey -Name 'IPv4Configured') -eq 1
            $v6Configured = (Get-RegistryValue -SubKeyPath $adapterBackupKey -Name 'IPv6Configured') -eq 1
            $dohV4Added = @(Split-NameServerList -Value ([string](Get-RegistryValue -SubKeyPath $adapterBackupKey -Name 'DohIPv4Added')))
            $dohV6Added = @(Split-NameServerList -Value ([string](Get-RegistryValue -SubKeyPath $adapterBackupKey -Name 'DohIPv6Added')))

            $dohRoot = "SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$guid\DohInterfaceSettings"
            foreach ($ip in $dohV4Added) {
                Remove-RegistrySubKeyTree -SubKeyPath "$dohRoot\Doh\$ip"
            }
            foreach ($ip in $dohV6Added) {
                Remove-RegistrySubKeyTree -SubKeyPath "$dohRoot\Doh6\$ip"
            }

            $adapter = $allAdapters | Where-Object { $_.InterfaceGuid -ieq $guid } | Select-Object -First 1
            if ($null -eq $adapter) {
                continue
            }

            $ifIndex = $adapter.ifIndex
            $v4List = @(Split-NameServerList -Value $origV4)
            $v6List = @(Split-NameServerList -Value $origV6)
            $needsReset = ($v4Configured -and $v4List.Count -eq 0) -or ($v6Configured -and $v6List.Count -eq 0)

            if ($needsReset) {
                Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ResetServerAddresses -ErrorAction Stop
                if ($v4List.Count -gt 0) {
                    Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses $v4List -ErrorAction Stop
                }
                if ($v6List.Count -gt 0) {
                    Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses $v6List -ErrorAction Stop
                }
            }
            else {
                if ($v4Configured -and $v4List.Count -gt 0) {
                    Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses $v4List -ErrorAction Stop
                }
                if ($v6Configured -and $v6List.Count -gt 0) {
                    Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses $v6List -ErrorAction Stop
                }
            }
        }
        catch {
            Write-Warning "Failed to restore DNS on adapter ${guid}: $_"
        }
    }

    Restore-GlobalCloudflareDoh
    Remove-RegistrySubKeyTree -SubKeyPath $BackupRootSubKey
    Clear-DnsClientCache -ErrorAction SilentlyContinue
}

switch ($Action) {
    'Install' { Install-CloudflareDns }
    'Uninstall' { Uninstall-CloudflareDns }
}
