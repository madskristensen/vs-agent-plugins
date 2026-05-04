# Bootstrap + helper functions for the controlling-visual-studio skill.
#
# Dot-source from anywhere:
#     . 'C:\path\to\skills\controlling-visual-studio\scripts\Connect-VsDte.ps1'
#
# Then use:
#     $dte = Get-VsDte
#     Open-VsFile -Path C:\foo.cs -Line 42
#     Invoke-VsCommand 'File.SaveAll'
#     Invoke-VsBuild -TimeoutSeconds 600
#     Invoke-WithComRetry { $dte.Solution.SolutionBuild.Build($true) }

$ErrorActionPreference = 'Stop'

# --- DLL load (idempotent) ---------------------------------------------------
if (-not ('RotHelper' -as [type])) {
	$dll = Join-Path $PSScriptRoot 'RotHelper.dll'
	if (-not (Test-Path -LiteralPath $dll)) {
		throw "RotHelper.dll not found at $dll. Rebuild it with src/build.ps1."
	}
	Add-Type -Path $dll -ErrorAction Stop
}

# --- STA warning (DTE prefers STA; pwsh 7+ defaults to MTA) ------------------
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
	Write-Verbose "Apartment is $([System.Threading.Thread]::CurrentThread.GetApartmentState()). Some DTE calls may fail; restart with: pwsh -STA"
}

# --- COM retry helper --------------------------------------------------------
function Invoke-WithComRetry {
	param(
		[Parameter(Mandatory)][scriptblock]$Script,
		[int]$MaxAttempts = 8,
		[int]$InitialDelayMs = 50
	)
	$delay = $InitialDelayMs
	for ($i = 1; $i -le $MaxAttempts; $i++) {
		try { return & $Script }
		catch [System.Runtime.InteropServices.COMException] {
			$hr = $_.Exception.HResult
			# 0x80010001 RPC_E_CALL_REJECTED, 0x8001010A RPC_E_SERVERCALL_RETRYLATER
			if ($hr -ne -2147418111 -and $hr -ne -2147417846) { throw }
			if ($i -eq $MaxAttempts) { throw }
			Start-Sleep -Milliseconds $delay
			$delay = [Math]::Min($delay * 2, 1000)
		}
	}
}

# --- DTE acquisition ---------------------------------------------------------
function Get-HostDevenvPid {
	$result = [ProcessHelper]::FindAncestorByName($PID, 'devenv')
	if ($result -gt 0) { [int]$result } else { $null }
}

function Get-DteByPid {
	param([Parameter(Mandatory)][int]$ProcessId, [string]$VersionFragment = 'VisualStudio.DTE')
	$matches = [RotHelper]::Find($VersionFragment) | Where-Object { $_.Key -match ":$ProcessId$" }
	if ($matches.Count -eq 0) { return $null }
	return $matches[0].Value
}

function Get-VsDte {
	[CmdletBinding()]
	param(
		# Substring of Solution.FullName to disambiguate when not running under devenv.
		[string]$SolutionMatch
	)
	# Reuse cached instance if still alive.
	if ($script:__dte) {
		try { $null = $script:__dte.Version; return $script:__dte } catch { $script:__dte = $null }
	}

	# 1. Preferred: PID match via parent-process walk.
	$vsPid = Get-HostDevenvPid
	if ($vsPid) { $script:__dte = Get-DteByPid -ProcessId $vsPid }

	# 2. Fallback: filter by solution name.
	if (-not $script:__dte -and $SolutionMatch) {
		$script:__dte = [RotHelper]::Find('VisualStudio.DTE') |
			ForEach-Object { $_.Value } |
			Where-Object { try { $_.Solution.FullName -like "*$SolutionMatch*" } catch { $false } } |
			Select-Object -First 1
	}

	# 3. Last resort: first instance.
	if (-not $script:__dte) {
		$script:__dte = [RotHelper]::Find('VisualStudio.DTE') |
			Select-Object -First 1 | ForEach-Object { $_.Value }
	}

	if (-not $script:__dte) {
		$devenvCount = @(Get-Process devenv -ErrorAction SilentlyContinue).Count
		if ($devenvCount -gt 0) {
			throw "Found $devenvCount devenv.exe process(es) but none are visible in the ROT. Likely cause: integrity-level mismatch between Visual Studio and this pwsh session. Run pwsh at the same elevation as Visual Studio."
		}
		throw 'No running Visual Studio instance found.'
	}
	return $script:__dte
}

# --- High-level verbs --------------------------------------------------------
function Open-VsFile {
	param(
		[Parameter(Mandatory)][string]$Path,
		[int]$Line = 0,
		[int]$Column = 1
	)
	$dte = Get-VsDte
	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "File not found: $Path" }
	$full = [System.IO.Path]::GetFullPath($Path)
	$window = Invoke-WithComRetry { $dte.ItemOperations.OpenFile($full) }
	if ($Line -gt 0 -and $window) {
		try {
			$sel = $window.Document.Selection
			if ($sel) { Invoke-WithComRetry { $sel.MoveToLineAndOffset($Line, [Math]::Max(1, $Column)) } | Out-Null }
		} catch { Write-Verbose "Could not navigate to ${Line}:${Column} in $full ($_)" }
	}
	return $window
}

function Invoke-VsCommand {
	param(
		[Parameter(Mandatory)][string]$Name,
		[string]$Args = ''
	)
	$dte = Get-VsDte
	Invoke-WithComRetry { $dte.ExecuteCommand($Name, $Args) }
}

function Invoke-VsBuild {
	param(
		[int]$TimeoutSeconds = 600,
		[switch]$WaitForBuildToFinish
	)
	$dte = Get-VsDte
	$sb  = $dte.Solution.SolutionBuild
	$sb.Build($WaitForBuildToFinish.IsPresent)
	if ($WaitForBuildToFinish) { return $sb.LastBuildInfo }

	# Async: poll BuildState (vsBuildStateNotStarted=0, InProgress=1, Done=2)
	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	while ($sb.BuildState -ne 2) {
		if ((Get-Date) -gt $deadline) { throw "Build did not finish within $TimeoutSeconds s." }
		Start-Sleep -Milliseconds 250
	}
	return $sb.LastBuildInfo
}
