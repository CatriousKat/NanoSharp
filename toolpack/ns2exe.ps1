<#
.SYNOPSIS
    ns2exe - NanoSharp to Executable Compiler (using nanosharp.exe)
.DESCRIPTION
    Embeds a NanoSharp .ns script and nanosharp.exe as resources into a single standalone executable.
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

$exeSource = Join-Path (Get-Location) "nanosharp.exe"
if (-not (Test-Path $exeSource)) {
    Write-Warning "Warning: nanosharp.exe not found in root directory."
}

$csCode = @"
using System;
using System.IO;
using System.Reflection;
using System.Diagnostics;

class Program {
    static void Main(string[] args) {
        try {
            string tempDir = Path.Combine(Path.GetTempPath(), "NanoSharpRuntime_" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(tempDir);

            string exePath = Path.Combine(tempDir, "nanosharp.exe");
            string scriptPath = Path.Combine(tempDir, "script.ns");

            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("nanosharp.exe")) {
                if (s != null) {
                    using (FileStream fs = new FileStream(exePath, FileMode.Create, FileAccess.Write)) {
                        s.CopyTo(fs);
                    }
                }
            }

            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("script.ns")) {
                if (s != null) {
                    using (FileStream fs = new FileStream(scriptPath, FileMode.Create, FileAccess.Write)) {
                        s.CopyTo(fs);
                    }
                }
            }

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = exePath;
            psi.Arguments = "\"" + scriptPath + "\"";
            psi.UseShellExecute = false;

            Process p = Process.Start(psi);
            p.WaitForExit();

            try { Directory.Delete(tempDir, true); } catch { }

            Environment.Exit(p.ExitCode);
        } catch (Exception ex) {
            Console.WriteLine("Error executing NanoSharp wrapper: " + ex.Message);
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
    
    $resourceArgs = ""
    if (Test-Path $exeSource) {
        $resourceArgs += " /resource:`"$exeSource`",nanosharp.exe"
    }
    if (Test-Path $ScriptPath) {
        $resourceArgs += " /resource:`"$ScriptPath`",script.ns"
    }

    $psi.Arguments = "/target:exe /out:`"$OutPath`"$resourceArgs `"$tempCs`""
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = false
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.WaitForExit()
    
    Remove-Item $tempCs -ErrorAction SilentlyContinue
    Write-Host "Successfully compiled standalone executable to $OutPath" -ForegroundColor Green
} else {
    Write-Error "C# compiler (csc.exe) not found on this system."
    exit 1
}
