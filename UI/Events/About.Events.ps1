$GitHubProfileButton.Add_Click({ try { Start-Process $script:GitHubProfileUrl } catch { Show-AppError $_.Exception.Message } })
$RepositoryButton.Add_Click({ try { Start-Process $script:RepositoryUrl } catch { Show-AppError $_.Exception.Message } })
$KoFiButton.Add_Click({ try { Start-Process $script:KoFiUrl } catch { Show-AppError $_.Exception.Message } })
$CheckUpdatesButton.Add_Click({
    Set-Busy $true (T 'CheckingUpdates')
    Set-UpdateCheckResult -State Checking -Message (T 'CheckingUpdates')
    try {
        $release = Get-LatestGitHubRelease
        if ($null -eq $release) {
            $UpdateCheckStatus.Tag='Result'
            $UpdateCheckStatus.Text=T 'UpToDate'
            Set-UpdateCheckResult -State Success -Message (T 'UpToDate')
        }
        else {
            $tag = ([string]$release.tag_name).Trim().TrimStart('v','V')
            $latest = $null
            if (-not [Version]::TryParse($tag, [ref]$latest)) { throw (T 'InvalidReleaseVersion') }
            if ($latest -gt [Version]'1.0.0') {
                $UpdateCheckStatus.Tag = 'Result'; $UpdateCheckStatus.Text = TF 'UpdateAvailableStatus' @($release.tag_name)
                Set-UpdateCheckResult -State Available -Message (TF 'UpdateAvailableStatus' @($release.tag_name)) -ReleaseUrl ([string]$release.html_url)
            }
            else {
                $UpdateCheckStatus.Tag='Result'
                $UpdateCheckStatus.Text=T 'UpToDate'
                Set-UpdateCheckResult -State Success -Message (T 'UpToDate')
            }
        }
    }
    catch { $UpdateCheckStatus.Tag='Result'; $UpdateCheckStatus.Text=T 'UpdateCheckFailed'; Set-UpdateCheckResult -State Error -Message (T 'UpdateCheckFailed') }
    finally { Set-Busy $false '' }
})
$UpdateResultAction.Add_Click({ if (-not [string]::IsNullOrWhiteSpace([string]$script:PendingReleaseUrl)) { try { Start-Process ([string]$script:PendingReleaseUrl) } catch { Set-UpdateCheckResult -State Error -Message (T 'UpdateCheckFailed') } } })
$UpdateResultClose.Add_MouseEnter({ $UpdateResultClose.Foreground = [Windows.Media.Brushes]::White })
$UpdateResultClose.Add_MouseLeave({ if ($script:UpdateResultCloseBrush) { $UpdateResultClose.Foreground = $script:UpdateResultCloseBrush } })
$UpdateResultClose.Add_Click({ Hide-UpdateCheckResult })
