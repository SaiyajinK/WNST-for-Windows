function Invoke-HuGitHubApi {
    param([Parameter(Mandatory=$true)][string]$Uri)

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
    catch { }

    $headers = @{
        'User-Agent' = 'WNST/1.0.0'
        'Accept' = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2026-03-10'
    }

    return Invoke-RestMethod -Uri $Uri -Headers $headers -Method Get -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
}

function Get-LatestGitHubRelease {
    $repositoryApi = 'https://api.github.com/repos/SaiyajinK/WNST-for-Windows'
    $latestReleaseApi = $repositoryApi + '/releases/latest'

    try {
        return Invoke-HuGitHubApi -Uri $latestReleaseApi
    }
    catch {
        $statusCode = $null
        try {
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
        }
        catch { }

        if ($statusCode -eq 404) {
            try {
                # Vérifie que le dépôt existe réellement.
                [void](Invoke-HuGitHubApi -Uri $repositoryApi)
                # Dépôt accessible + /releases/latest en 404 = aucune release publiée.
                return $null
            }
            catch {
                throw
            }
        }

        throw
    }
}

function Set-UpdateCheckResult {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Checking','Success','Available','Error')][string]$State,
        [Parameter(Mandatory=$true)][string]$Message,
        [AllowEmptyString()][string]$ReleaseUrl = ''
    )
    $colors = switch ($State) {
        'Success' { if ($script:ResolvedTheme -eq 'Light') { @('#E7F5EE','#107C10','#236B45') } else { @('#1E322A','#4CC38A','#B6F0D2') } }
        'Available' { if ($script:ResolvedTheme -eq 'Light') { @('#FFF4DD','#D8A126','#7A5500') } else { @('#332C1E','#E5AA42','#F1D39C') } }
        'Error' { if ($script:ResolvedTheme -eq 'Light') { @('#FDEBEC','#D13438','#8A1C20') } else { @('#3A2023','#D13438','#FFB3B6') } }
        default { if ($script:ResolvedTheme -eq 'Light') { @('#EAF4FC','#1A9FFF','#155A8A') } else { @('#1D2B36','#1A9FFF','#B9E4FF') } }
    }
    $UpdateResultPanel.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($colors[0]))
    $stateBrush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($colors[1]))
    $UpdateResultPanel.BorderBrush = $stateBrush
    $UpdateResultDot.Fill = $stateBrush
    $script:UpdateResultCloseBrush = $stateBrush
    $UpdateResultClose.Foreground = $stateBrush
    $UpdateResultText.Foreground = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($colors[2]))
    $UpdateResultText.Text = $Message
    $UpdateResultPanel.Tag = $State
    $UpdateResultPanel.Visibility = 'Visible'
    $script:PendingReleaseUrl = $ReleaseUrl
    $UpdateResultAction.Visibility = if ($State -eq 'Available' -and -not [string]::IsNullOrWhiteSpace($ReleaseUrl)) { 'Visible' } else { 'Collapsed' }
}

function Hide-UpdateCheckResult {
    $UpdateResultPanel.Visibility = 'Collapsed'
    $UpdateResultPanel.Tag = $null
    $UpdateResultText.Text = ''
    $UpdateResultAction.Visibility = 'Collapsed'
    $script:PendingReleaseUrl = ''
    $UpdateCheckStatus.Tag = $null
    $UpdateCheckStatus.Text = T 'UpdateCheckHint'
}
