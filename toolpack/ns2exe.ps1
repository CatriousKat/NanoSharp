<#
.SYNOPSIS
    ns2exe - NanoSharp to Executable Compiler
.DESCRIPTION
    A PowerShell GUI and CLI utility to embed NanoSharp .ns scripts and load nanosharp.dll directly.
#>

param(
    [string]$ScriptPath,
    [string]$Arch
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Start-CliMode {
    param([string]$script, [string]$architecture)
    
    if (-not $script -or -not (Test-Path $script)) {
        Write-Host "Error: Valid .ns script path required." -ForegroundColor Red
        exit 1
    }
    
    if (-not $architecture) {
        $architecture = "amd64"
    }

    Invoke-Compile -Script $script -Arch $architecture
    exit 0
}

function Invoke-Compile {
    param([string]$Script, [string]$Arch)

    $buildDir = Join-Path (Get-Location) "build"
    if (-not (Test-Path $buildDir)) {
        [void][System.IO.Directory]::CreateDirectory($buildDir)
    }

    $dllSource = Join-Path (Get-Location) "nanosharp.dll"
    $destDll = Join-Path $buildDir "nanosharp.dll"
    if (Test-Path $dllSource) {
        Copy-Item -Path $dllSource -Destination $destDll -Force
    } else {
        Write-Host "Warning: nanosharp.dll not found in root directory." -ForegroundColor Yellow
    }

    $scriptContent = [System.IO.File]::ReadAllText($Script)
    # Safely escape string content for injection into a C# verbatim string literal by replacing quotes with double quotes
    $escapedScript = $scriptContent.Replace('"', '""')

    $miniExeName = [System.IO.Path]::GetFileNameWithoutExtension($Script) + ".exe"
    $miniExePath = Join-Path $buildDir $miniExeName

    # Generate a C# wrapper that embeds the script content and calls nanosharp.dll directly via P/Invoke
    $csCode = @"
using System;
using System.Runtime.InteropServices;
using System.IO;

class Program {
    [DllImport("nanosharp.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    public static extern void RunNanoSharpCode(string code);

    static void Main(string[] args) {
        string embeddedScript = 
@"$escapedScript";

        try {
            RunNanoSharpCode(embeddedScript);
        } catch (Exception ex) {
            Console.WriteLine("Error executing script: " + ex.Message);
        }
    }
}
"@

    $tempCs = Join-Path $env:TEMP "nanosharp_embedded.cs"
    [System.IO.File]::WriteAllText($tempCs, $csCode, [System.Text.Encoding]::UTF8)

    $cscPath = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    if (-not (Test-Path $cscPath)) {
        $cscPath = "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
    }

    if (Test-Path $cscPath) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $cscPath
        $psi.Arguments = "/target:exe /out:`"$miniExePath`" `"$tempCs`""
        $psi.CreateNoWindow = $true
        $psi.UseShellExecute = false
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit()
        Remove-Item $tempCs -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show("Successfully compiled standalone executable to build\`$miniExeName!", "ns2exe Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } else {
        [System.Windows.Forms.MessageBox]::Show("C# compiler (csc.exe) not found on this system.", "Compilation Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

if ($ScriptPath) {
    Start-CliMode -script $ScriptPath -architecture $Arch
}

# --- GUI Mode ---

$form = New-Object System.Windows.Forms.Form
$form.Text = "ns2exe Compiler"
$form.Size = New-Object System.Drawing.Size(460, 260)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false

$lblScript = New-Object System.Windows.Forms.Label
$lblScript.Location = New-Object System.Drawing.Point(20, 20)
$lblScript.Size = New-Object System.Drawing.Size(100, 20)
$lblScript.Text = ".ns Script:"
$form.Controls.Add($lblScript)

$txtScript = New-Object System.Windows.Forms.TextBox
$txtScript.Location = New-Object System.Drawing.Point(20, 45)
$txtScript.Size = New-Object System.Drawing.Size(310, 23)
$form.Controls.Add($txtScript)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Location = New-Object System.Drawing.Point(340, 44)
$btnBrowse.Size = New-Object System.Drawing.Size(80, 25)
$btnBrowse.Text = "Browse..."
$btnBrowse.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "NanoSharp Scripts (*.ns)|*.ns|All Files (*.*)|*.*"
    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtScript.Text = $ofd.FileName
    }
})
$form.Controls.Add($btnBrowse)

$lblArch = New-Object System.Windows.Forms.Label
$lblArch.Location = New-Object System.Drawing.Point(20, 90)
$lblArch.Size = New-Object System.Drawing.Size(100, 20)
$lblArch.Text = "Architecture:"
$form.Controls.Add($lblArch)

$cmbArch = New-Object System.Windows.Forms.ComboBox
$cmbArch.Location = New-Object System.Drawing.Point(20, 115)
$cmbArch.Size = New-Object System.Drawing.Size(200, 23)
$cmbArch.Items.AddRange(@("amd64", "386", "arm64"))
$cmbArch.SelectedIndex = 0
$form.Controls.Add($cmbArch)

$btnCompile = New-Object System.Windows.Forms.Button
$btnCompile.Location = New-Object System.Drawing.Point(320, 170)
$btnCompile.Size = New-Object System.Drawing.Size(100, 30)
$btnCompile.Text = "Compile"
$btnCompile.Add_Click({
    if ([string]::IsNullOrWhiteSpace($txtScript.Text) -or -not (Test-Path $txtScript.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Please select a valid .ns script file.", "Validation Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    Invoke-Compile -Script $txtScript.Text -Arch $cmbArch.SelectedItem.ToString()
})
$form.Controls.Add($btnCompile)

[void]$form.ShowDialog()
