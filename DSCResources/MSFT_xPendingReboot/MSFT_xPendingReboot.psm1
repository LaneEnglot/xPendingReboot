Function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([Hashtable])
     param
    (
    [Parameter(Mandatory=$true)]
    [string]$Name
    )

    $ComponentBasedServicing = (Get-ChildItem 'hklm:SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\').Name.Split("\") -contains "RebootPending"
    $WindowsUpdate = (Get-ChildItem 'hklm:SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\').Name.Split("\") -contains "RebootRequired"
    $PendingFileRename = (Get-ItemProperty 'hklm:\SYSTEM\CurrentControlSet\Control\Session Manager\').PendingFileRenameOperations.Length -gt 0
    $ActiveComputerName = (Get-ItemProperty 'hklm:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName').ComputerName
    $PendingComputerName = (Get-ItemProperty 'hklm:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName').ComputerName
    $PendingComputerRename = $ActiveComputerName -ne $PendingComputerName
    
    $CCMSplat = @{
        NameSpace='ROOT\ccm\ClientSDK'
        Class='CCM_ClientUtilities'
        Name='DetermineIfRebootPending'
        ErrorAction='Stop'
    }

    Try {
        $CCMClientSDK = Invoke-WmiMethod @CCMSplat
    } Catch {
        Write-Warning "Unable to query CCM_ClientUtilities: $_"
    }

    $SCCMSDK = ($CCMClientSDK.ReturnValue -eq 0) -and ($CCMClientSDK.IsHardRebootPending -or $CCMClientSDK.RebootPending)

    return @{
    Name = $Name
    ComponentBasedServicing = $ComponentBasedServicing
    WindowsUpdate = $WindowsUpdate
    PendingFileRename = $PendingFileRename
    PendingComputerRename = $PendingComputerRename
    CcmClientSDK = $SCCMSDK
    }
}

Function Set-TargetResource
{
    [CmdletBinding()]
     param
    (
    [Parameter(Mandatory=$true)]
    [string]$Name,
    [bool]$SkipComponentBasedServicing,
    [bool]$SkipWindowsUpdate,
    [bool]$SkipPendingFileRename,
    [bool]$SkipPendingComputerRename,
    [bool]$SkipCcmClientSDK
    )

    $global:DSCMachineStatus = 1
}

Function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([Boolean])]
     param
    (
    [Parameter(Mandatory=$true)]
    [string]$Name,
    [bool]$SkipComponentBasedServicing,
    [bool]$SkipWindowsUpdate,
    [bool]$SkipPendingFileRename,
    [bool]$SkipPendingComputerRename,
    [bool]$SkipCcmClientSDK
    )

    if(-not $SkipComponentBasedServicing)
    {
        $ScriptBlocks += @{ComponentBasedServicing = {(Get-ChildItem 'hklm:SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\').Name.Split("\") -contains "RebootPending"}}
    }

    if(-not $SkipWindowsUpdate)
    {
        $ScriptBlocks += @{WindowsUpdate = {(Get-ChildItem 'hklm:SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\').Name.Split("\") -contains "RebootRequired"}}
    }

    if(-not $SkipPendingFileRename)
    {
        $ScriptBlocks += @{PendingFileRename = {(Get-ItemProperty 'hklm:\SYSTEM\CurrentControlSet\Control\Session Manager\').PendingFileRenameOperations.Length -gt 0}}
    }

    if(-not $SkipPendingComputerRename)
    {
        $ScriptBlocks += @{PendingComputerRename = {
                $ActiveComputerName = (Get-ItemProperty 'hklm:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName').ComputerName
                $PendingComputerName = (Get-ItemProperty 'hklm:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName').ComputerName
                $ActiveComputerName -ne $PendingComputerName
            }
        }
    }

    if(-not $SkipCcmClientSDK)
    {
        $ScriptBlocks += @{CcmClientSDK = {
                $CCMSplat = @{
                    NameSpace='ROOT\ccm\ClientSDK'
                    Class='CCM_ClientUtilities'
                    Name='DetermineIfRebootPending'
                    ErrorAction='Stop'
                }
                Try {
                    $CCMClientSDK = Invoke-WmiMethod @CCMSplat
                    ($CCMClientSDK.ReturnValue -eq 0) -and ($CCMClientSDK.IsHardRebootPending -or $CCMClientSDK.RebootPending)
                } Catch {
                    Write-Warning "Unable to query CCM_ClientUtilities: $_"
                }
            }
        }
    }

    Foreach ($Script in $ScriptBlocks.Keys) {
        If (Invoke-Command $ScriptBlocks[$Script]) {
            Write-Verbose "A pending reboot was found for $Script."
            Write-Verbose 'Setting the DSCMachineStatus global variable to 1.'
            return $false
        }
    }

    Write-Verbose 'No pending reboots found.'
    return $true
}

Export-ModuleMember -Function *-TargetResource

$regRebootLocations = $null
