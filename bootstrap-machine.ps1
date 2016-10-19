﻿# variables (both powershell and bash versions)
$user = Get-CimInstance Win32_UserAccount | Where-Object { $_.Caption -eq $(whoami) }
$ps = New-Object PSObject -Property @{
    NudgeDir = "$env:ProgramData\Nudge"
    SetupDir = "$env:ProgramData\Nudge\machine-setup"
    EmailAddressFile = "$env:ProgramData\Nudge\machine-setup\emailaddress.txt"
    CodeDir = "C:\Code"
    UserDir = "$env:USERPROFILE" 
    SshDir = "$env:USERPROFILE\.ssh"
}
$bash = New-Object PSObject
foreach ($p in Get-Member -InputObject $ps -MemberType NoteProperty) {
     Add-Member -InputObject $bash -MemberType NoteProperty -Name $p.Name -Value $From.$($p.Name) –Force
     $bash.$($p.Name) = $($ps.$($p.Name) -replace "\\", "/" -replace "C:", "/c")
}

Write-Host ">> Prerequisites validation"
$os = Get-CimInstance Win32_OperatingSystem
$prerequisites = New-Object PSObject -Property @{
    OSHasVersion = $os.Version -gt 10
    OSHasArchitecture = $os.OSArchitecture -eq '64-bit'
    OSHasType = ($os.Caption -like '*Pro*') -or ($os.Caption -like '*Enterprise*')
    UserNameValid = $env:UserName -notlike '* *'
}
if (!$prerequisites.OSHasVersion -or !$prerequisites.OSHasArchitecture -or !$prerequisites.OSHasType -or !$prerequisites.UserNameValid) {
    if (!$prerequisites.OSHasVersion -or !$prerequisites.OSHasArchitecture -or !$prerequisites.OSHasType) { Write-Host "Minimum supported version of Windows is Windows 10 Pro, 64-bit. You are running $($os.Caption), $($os.OSArchitecture)" }
    if (!$prerequisites.UserNameValid) { Write-Host "UserName ($env:UserName) must not contain spaces: Modify in Start -> User Accounts before continuing" }
#    if (!$prerequisites.UserMicrosoftAccount) { Write-Host "User account must be linked to Microsoft account (see https://support.microsoft.com/en-us/help/17201/windows-10-sign-in-with-a-microsoft-account)" }
    Exit
}

Write-Host ">> Logging is in $env:LocalAppData\Boxstarter\Boxstarter.log, available from link on Desktop"
Install-ChocolateyShortcut -ShortcutFilePath "$env:USERPROFILE\Desktop\Boxstarter Log.lnk"  -TargetPath $env:LocalAppData\Boxstarter\Boxstarter.log

if (!(Test-Path $ps.EmailAddressFile)) {
    $emailAddress = Read-Host "What email do you use with git? "  
    New-Item $ps.EmailAddressFile -Force
    Add-Content -Path $ps.EmailAddressFile -Value "$emailAddress"
} else {
    $emailAddress = Get-Content -Path $ps.EmailAddressFile
}
Write-Host ">> Email Address: $emailAddress"

Write-Host ">> Update Boxstarter"
$lockFile = "$($ps.SetupDir)\bootstrap-machine.lock"
if (!(Test-Path $lockFile -NewerThan (Get-Date).AddHours(-2))) {
    if (Test-PendingReboot) { Invoke-Reboot }
    # chocolatey initial setup
    choco feature enable -n=allowGlobalConfirmation -y
    choco feature enable -n=autoUninstaller -y
    & "$env:windir\Microsoft.NET\Framework64\v2.0.50727\ldr64" set64

    # Windows setup
    Set-WindowsExplorerOptions -EnableShowHiddenFilesFoldersDrives -EnableShowProtectedOSFiles -EnableShowFileExtensions -EnableShowFullPathInTitleBar
    Disable-InternetExplorerESC
    Update-ExecutionPolicy
    Update-ExecutionPolicy Unrestricted
    cinst boxstarter -y
    New-Item $lockFile -Force
}

Write-Host ">> Install git"
$lockFile = "$($ps.SetupDir)\install-git.lock"
if (!(Test-Path $lockFile)) {
    if (Test-PendingReboot) { Invoke-Reboot }
    # git install
    cinst git -y -params '"/GitAndUnixToolsOnPath /NoAutoCrlf"'
    cinst poshgit -y
    cinst gitextensions -y
    New-Item $lockFile -Force
    Invoke-Reboot
}

Write-Host ">> Setup git & github"
$lockFile = "$($ps.SetupDir)\setup-git.lock"
if (!(Test-Path $lockFile)) {
    git config --global user.name $user.FullName
    git config --global user.email $emailAddress
    git config --global core.autocrlf False

    # git ssh setup
    if (!(Test-Path "$($ps.SshDir)\id_rsa")) {
        ssh-keygen -q -C $emailAddress -f "$($bash.SshDir)/id_rsa"
    }

    ssh-agent -s
    ssh-add "$($bash.SshDir)/id_rsa"
    Get-Content "$($ps.SshDir)\id_rsa.pub" | clip

    # because of the context, can't use Edge to open github at this point
    cinst googlechrome -y
    cinst lastpass -y
    & notepad "$($ps.SshDir)\id_rsa.pub"
    & "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe" "https://github.com/settings/ssh"

    Write-Host "Copied the full contents of $($bash.SshDir)/id_rsa.pub (currently in your clipboard):"
    Write-Host "Go to https://github.com/settings/ssh and add as a new key, then press ENTER"
    Write-Host ""
    Read-Host "The below (Could not find exported function RelaunchChromeBrowserWithNewCommandLineIfNeeded) can be ignored."
    ssh -T git@github.com
    New-Item $lockFile -Force
}

Write-Host ">> Update Windows"
$lockFile = "$($ps.SetupDir)\windows-update.lock"
if (!(Test-Path $lockFile -NewerThan (Get-Date).AddHours(-2))) {
    if (Test-PendingReboot) { Invoke-Reboot }

    Install-WindowsUpdate  -AcceptEula
    New-Item $lockFile -Force
}

Write-Host ">> Pull code from github"
if (!(Test-Path $ps.CodeDir)) {
    New-Item -Path $ps.CodeDir -type Directory
}
$repo = "Tooling"
if (!(Test-Path "$($ps.CodeDir)\$repo")) {
    git clone git@github.com:NudgeSoftware/$repo.git "$($ps.CodeDir)\$repo"
    cp "$($ps.CodeDir)\$repo\config\dev\*" $ps.SetupDir
}
$repo = "Relationships"
if (!(Test-Path "$($ps.CodeDir)\$repo")) {
    git clone git@github.com:NudgeSoftware/$repo.git "$($ps.CodeDir)\$repo"
}

#& "$($ps.SetupDir)\Install-Environment.ps1" -setupDir $ps.SetupDir -nudgeDir $ps.NudgeDir -codeDir $ps.CodeDir -emailAddress $emailAddress
#Enable-MicrosoftUpdate
#Enable-UAC
