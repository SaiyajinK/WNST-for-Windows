function Resolve-HuSourceUri {
    param([Parameter(Mandatory = $true)][string]$SourceUrl)

    $value = $SourceUrl.Trim()
    if ([string]::IsNullOrWhiteSpace($value) -or $value -match '[\x00-\x20\\]') {
        throw (Get-HuModuleText 'SourceAddressInvalid')
    }
    $uri = $null
    if (-not [Uri]::TryCreate($value, [UriKind]::Absolute, [ref]$uri)) {
        throw (Get-HuModuleText 'SourceAddressInvalid')
    }
    if ($uri.Scheme.ToLowerInvariant() -notin @('http', 'https', 'ftp')) {
        throw (Get-HuModuleText 'SourceSchemeInvalid')
    }
    if ([string]::IsNullOrWhiteSpace($uri.Host) -or [Uri]::CheckHostName($uri.Host) -eq [UriHostNameType]::Unknown) {
        throw (Get-HuModuleText 'SourceHostInvalid')
    }
    if (-not [string]::IsNullOrWhiteSpace($uri.UserInfo)) {
        throw (Get-HuModuleText 'SourceCredentialsInvalid')
    }
    return $uri
}

function Test-HuSourceAddress {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$SourceUrl)
    try {
        [void](Resolve-HuSourceUri -SourceUrl $SourceUrl)
        return $true
    }
    catch { return $false }
}

function Get-HuFtpText {
    param(
        [Parameter(Mandatory=$true)][Uri]$Uri,
        [ValidateRange(5,120)][int]$TimeoutSeconds,
        [ValidateRange(1024,52428800)][int]$MaximumBytes
    )
    $request = [Net.FtpWebRequest][Net.WebRequest]::Create($Uri)
    $request.Method = [Net.WebRequestMethods+Ftp]::DownloadFile
    $request.Timeout = $TimeoutSeconds * 1000
    $request.ReadWriteTimeout = $TimeoutSeconds * 1000
    $request.UseBinary = $true
    $request.UsePassive = $true
    $request.KeepAlive = $false
    $request.Credentials = New-Object Net.NetworkCredential('anonymous', ("WNST/{0}" -f $script:ToolVersion))
    $response = $null
    $stream = $null
    $memory = New-Object IO.MemoryStream
    try {
        $response = [Net.FtpWebResponse]$request.GetResponse()
        $stream = $response.GetResponseStream()
        $buffer = New-Object byte[] 8192
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if (($memory.Length + $read) -gt $MaximumBytes) { throw (Get-HuModuleText 'SourceListTooLarge') }
            $memory.Write($buffer, 0, $read)
        }
        $memory.Position = 0
        $reader = New-Object IO.StreamReader($memory, [Text.Encoding]::UTF8, $true, 4096, $true)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
    finally {
        if ($stream) { $stream.Dispose() }
        if ($response) { $response.Close() }
        $memory.Dispose()
    }
}

function Get-HuRemoteText {
    param(
        [Parameter(Mandatory = $true)][string]$SourceUrl,
        [ValidateRange(5, 120)][int]$TimeoutSeconds = 30,
        [ValidateRange(1024, 52428800)][int]$MaximumBytes = 10485760
    )

    $uri = Resolve-HuSourceUri -SourceUrl $SourceUrl
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
    catch { }

    try {
        if ($uri.Scheme -eq 'ftp') {
            $content = Get-HuFtpText -Uri $uri -TimeoutSeconds $TimeoutSeconds -MaximumBytes $MaximumBytes
        }
        else {
            $parameters = @{
                Uri         = $uri.AbsoluteUri
                Method      = 'Get'
                TimeoutSec  = $TimeoutSeconds
                ErrorAction = 'Stop'
                Headers     = @{ 'User-Agent' = "WNST/$script:ToolVersion" }
            }
            if ($PSVersionTable.PSVersion.Major -le 5) { $parameters.UseBasicParsing = $true }
            $response = Invoke-WebRequest @parameters
            $content = [string]$response.Content
        }
    }
    catch {
        throw (Format-HuModuleText 'SourceDownloadFailed' @($_.Exception.Message))
    }

    if ([Text.Encoding]::UTF8.GetByteCount($content) -gt $MaximumBytes) {
        throw (Get-HuModuleText 'SourceListTooLarge')
    }
    if ([string]::IsNullOrWhiteSpace($content)) {
        throw (Get-HuModuleText 'SourceListEmpty')
    }
    if ($content -match '(?is)^\s*(?:<!doctype\s+html|<html\b)' -or $content -match '(?is)<body\b') {
        throw (Get-HuModuleText 'SourceHtmlRejected')
    }
    return $content
}

function ConvertTo-HuDomainName {
    param([Parameter(Mandatory = $true)][string]$Value)

    $domain = $Value.Trim().TrimEnd('.').ToLowerInvariant()
    if (-not $domain -or $domain.Length -gt 253) { return $null }
    if ($domain -in @('localhost', 'localhost.localdomain', 'broadcasthost', 'ip6-localhost', 'ip6-loopback')) { return $null }
    if ($domain.Contains('*') -or $domain.Contains('/') -or $domain.Contains(':')) { return $null }

    try {
        $domain = (New-Object Globalization.IdnMapping).GetAscii($domain).ToLowerInvariant()
    }
    catch { return $null }

    $labels = $domain.Split('.')
    foreach ($label in $labels) {
        if ($label.Length -lt 1 -or $label.Length -gt 63) { return $null }
        if ($label -notmatch '^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$') { return $null }
    }
    return $domain
}

function ConvertFrom-HuHostsContent {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content)

    if ([string]::IsNullOrWhiteSpace($Content)) { throw (Get-HuModuleText 'SourceListEmpty') }
    if ($Content -match '(?is)^\s*(?:<!doctype\s+html|<html\b)' -or $Content -match '(?is)<body\b') {
        throw (Get-HuModuleText 'SourceHtmlRejected')
    }

    $entries = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $invalidLines = New-Object System.Collections.Generic.List[string]
    $ignoredLines = 0
    $lineNumber = 0

    foreach ($rawLine in @($Content -split "`r?`n")) {
        $lineNumber++
        $line = $rawLine.Trim().TrimStart([char]0xFEFF)
        if (-not $line -or $line.StartsWith('#')) { continue }
        $line = ($line -replace '\s+#.*$', '').Trim()
        if (-not $line) { continue }
        $tokens = @($line -split '\s+' | Where-Object { $_ })
        if ($tokens.Count -eq 0) { continue }

        $address = '0.0.0.0'
        $domainTokens = @()
        if ($tokens.Count -eq 1) {
            $domainTokens = @($tokens[0])
        }
        else {
            $ipAddress = $null
            if (-not [Net.IPAddress]::TryParse([string]$tokens[0], [ref]$ipAddress)) {
                $ignoredLines++
                $invalidLines.Add((Format-HuModuleText 'HostsInvalidLine' @($lineNumber, $rawLine.Trim())))
                continue
            }
            $address = $ipAddress.ToString()
            $domainTokens = @($tokens[1..($tokens.Count - 1)])
        }

        $lineAdded = $false
        foreach ($candidate in $domainTokens) {
            $domain = ConvertTo-HuDomainName -Value ([string]$candidate)
            if (-not $domain) { continue }
            if ($seen.Add($domain)) {
                $entries.Add([pscustomobject]@{ Address = $address; Domain = $domain })
                $lineAdded = $true
            }
        }
        if (-not $lineAdded) {
            $ignoredLines++
            $invalidLines.Add((Format-HuModuleText 'HostsInvalidLine' @($lineNumber, $rawLine.Trim())))
        }
    }

    if ($entries.Count -eq 0) {
        throw (Get-HuModuleText 'SourceNoValidHostsEntries')
    }

    return [pscustomobject]@{
        Entries      = @($entries.ToArray())
        EntryCount   = $entries.Count
        IgnoredLines = $ignoredLines
        InvalidLines = @($invalidLines.ToArray())
        CanonicalText = (@($entries | ForEach-Object { '{0} {1}' -f $_.Address, $_.Domain }) -join "`r`n")
    }
}

function Test-HuManualHostsEntries {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Content)

    if ([string]::IsNullOrWhiteSpace($Content)) {
        return [pscustomobject]@{ IsValid=$false; EntryCount=0; ErrorMessage=(Get-HuModuleText 'ManualEntryRequired'); InvalidLines=@() }
    }

    $invalid = New-Object System.Collections.Generic.List[string]
    $domains = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $lineNumber = 0
    foreach ($rawLine in @($Content -split "`r?`n")) {
        $lineNumber++
        $line = $rawLine.Trim().TrimStart([char]0xFEFF)
        if (-not $line -or $line.StartsWith('#')) { continue }
        $line = ($line -replace '\s+#.*$', '').Trim()
        if (-not $line) { continue }
        $tokens = @($line -split '\s+' | Where-Object { $_ })
        $domainToken = $null

        if ($tokens.Count -eq 1) {
            $parsedIp = $null
            if ([Net.IPAddress]::TryParse([string]$tokens[0], [ref]$parsedIp)) {
                $invalid.Add((Format-HuModuleText 'ManualLineIpNeedsHost' @($lineNumber)))
                continue
            }
            $domainToken = [string]$tokens[0]
        }
        elseif ($tokens.Count -eq 2) {
            $parsedIp = $null
            if (-not [Net.IPAddress]::TryParse([string]$tokens[0], [ref]$parsedIp)) {
                $invalid.Add((Format-HuModuleText 'ManualLineIpInvalid' @($lineNumber)))
                continue
            }
            $domainToken = [string]$tokens[1]
        }
        else {
            $invalid.Add((Format-HuModuleText 'ManualLineFormat' @($lineNumber)))
            continue
        }

        $domain = ConvertTo-HuDomainName -Value $domainToken
        if (-not $domain -or -not $domain.Contains('.') -or $domain -notmatch '[a-z]') {
            $invalid.Add((Format-HuModuleText 'ManualLineHostInvalid' @($lineNumber)))
            continue
        }
        [void]$domains.Add($domain)
    }

    if ($invalid.Count -gt 0) {
        $details = @($invalid | Select-Object -First 3) -join ' | '
        return [pscustomobject]@{ IsValid=$false; EntryCount=$domains.Count; ErrorMessage=(Format-HuModuleText 'ManualInvalidCount' @($invalid.Count,$details)); InvalidLines=@($invalid.ToArray()) }
    }
    if ($domains.Count -eq 0) {
        return [pscustomobject]@{ IsValid=$false; EntryCount=0; ErrorMessage=(Get-HuModuleText 'ManualEntryRequired'); InvalidLines=@() }
    }
    return [pscustomobject]@{ IsValid=$true; EntryCount=$domains.Count; ErrorMessage=''; InvalidLines=@() }
}

function Get-HuSha256Text {
    param([Parameter(Mandatory = $true)][string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Test-HuSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourceUrl,
        [ValidateRange(5, 120)][int]$TimeoutSeconds = 30
    )

    $content = Get-HuRemoteText -SourceUrl $SourceUrl -TimeoutSeconds $TimeoutSeconds
    $parsed = ConvertFrom-HuHostsContent -Content $content
    [pscustomobject]@{
        SourceUrl     = (Resolve-HuSourceUri -SourceUrl $SourceUrl).AbsoluteUri
        EntryCount    = $parsed.EntryCount
        IgnoredLines  = $parsed.IgnoredLines
        Sha256        = Get-HuSha256Text -Text $parsed.CanonicalText
        Sample        = @($parsed.Entries | Select-Object -First 5)
        RetrievedAt   = Get-Date
    }
}
