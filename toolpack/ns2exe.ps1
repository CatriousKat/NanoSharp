<#
.SYNOPSIS
    ns2exe - NanoSharp to Executable Compiler
.DESCRIPTION
    Compiles NanoSharp scripts into Windows PE executables.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ScriptPath,
    [string]$OutPath
)

if (-not (Test-Path $ScriptPath)) {
    Write-Error "Error: Valid .ns script path required."
    exit 1
}

if (-not $OutPath) {
    $OutPath = [System.IO.Path]::ChangeExtension($ScriptPath, ".exe")
}

$dllSource = Join-Path (Get-Location) "nanosharp.dll"
if (-not (Test-Path $dllSource)) {
    Write-Warning "Warning: nanosharp.dll not found in root directory."
}

$scriptContent = [System.IO.File]::ReadAllText($ScriptPath)
$escapedScript = $scriptContent.Replace('"', '""')

$csCode = @"
using System;
using System.Runtime.InteropServices;
using System.IO;
using System.Reflection;

class Program {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern IntPtr LoadLibrary(string lpFileName);

    [DllImport("nanosharp.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    public static extern void RunNanoSharpCode(string code);

    static void Main(string[] args) {
        try {
            string dllPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "nanosharp.dll");
            if (!File.Exists(dllPath)) {
                using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("nanosharp.dll")) {
                    if (s != null) {
                        using (FileStream fs = new FileStream(dllPath, FileMode.Create, FileAccess.Write)) {
                            s.CopyTo(fs);
                        }
                    }
                }
            }
            LoadLibrary(dllPath);
        } catch (Exception) { }

        string embeddedScript = 
@"$escapedScript";

        try {
            RunNanoSharpCode(embeddedScript);
        } catch (Exception ex) {
            System.Windows.Forms.MessageBox.Show("Error executing script: " + ex.Message, "NanoSharp Error", System.Windows.Forms.MessageBoxButtons.OK, System.Windows.Forms.MessageBoxIcon.Error);
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
    
    $resourceArg = ""
    if (Test-Path $dllSource) {
        $resourceArg = "/resource:`"$dllSource`",nanosharp.dll"
    }

    $psi.Arguments = "/target:exe /out:`"$OutPath`" $resourceArg `"$tempCs`""
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = false
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.WaitForExit()
    
    Remove-Item $tempCs -ErrorAction SilentlyContinue
    Write-Host "Successfully compiled executable to $OutPath" -ForegroundColor Green
} else {
    Write-Error "C# compiler (csc.exe) not found on this system."
    exit 1
}
