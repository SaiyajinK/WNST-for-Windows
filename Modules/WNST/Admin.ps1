function Test-HuAdministrator {
    [CmdletBinding()]
    param()

    if ($env:OS -ne 'Windows_NT') { return $false }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-HuAdministrator {
    if (-not (Test-HuAdministrator)) {
        throw (Get-HuModuleText 'AdministratorRequired')
    }
}
