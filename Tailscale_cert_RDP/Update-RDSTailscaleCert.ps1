 #!/usr/bin/env pwsh
# Script: Update-RDSTailscaleCert.ps1
# Description: Automatically updates Windows RDS certificate with Tailscale-generated certificate
# Requirements: Tailscale client, Admin privileges, MagicDNS and HTTPS Certificates enabled
# Usage: Run in elevated PowerShell. You'll need to set an appropriate Set-ExecutionPolicy.

# Step 1: Get the Tailscale hostname automatically
Write-Host "Detecting Tailscale hostname..." -ForegroundColor Cyan

$TailscaleStatus = tailscale status --json | ConvertFrom-Json
$TailscaleHostname = $TailscaleStatus.Self.DNSName.TrimEnd('.')

if ([string]::IsNullOrEmpty($TailscaleHostname)) {
    Write-Error "Could not detect Tailscale hostname. Is Tailscale running?"
    exit 1
}

Write-Host "Detected Tailscale hostname: $TailscaleHostname" -ForegroundColor Green

# Step 2: Generate Tailscale certificate
Write-Host "Generating Tailscale certificate..." -ForegroundColor Cyan
tailscale cert $TailscaleHostname

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to generate Tailscale certificate. Check that MagicDNS and HTTPS Certificates are enabled in Tailscale admin."
    exit 1
}

# Step 3: Locate the generated certificate files
# tailscale cert saves to current directory by default
$CertFile = "$TailscaleHostname.crt"
$KeyFile = "$TailscaleHostname.key"

if (-not (Test-Path $CertFile) -or -not (Test-Path $KeyFile)) {
    Write-Error "Certificate files not found. Expected $CertFile and $KeyFile in current directory."
    exit 1
}

Write-Host "Certificate files found: $CertFile and $KeyFile" -ForegroundColor Green

# Step 4: Convert to PFX using OpenSSL (requires OpenSSL to be installed)
$PfxFile = "$TailscaleHostname.pfx"

Write-Host "Converting to PFX format..." -ForegroundColor Cyan
Write-Host "NOTE: This requires OpenSSL. Install via: winget install OpenSSL.Light" -ForegroundColor Yellow

# Check if OpenSSL is available
$opensslPath = Get-Command openssl -ErrorAction SilentlyContinue

if (-not $opensslPath) {
    Write-Error @"
OpenSSL not found. Please install it first:
  winget install OpenSSL.Light
  
Or manually convert the certificate using another method.
"@
    exit 1
}

# Convert to PFX with no password (empty password)
& openssl pkcs12 -export -out $PfxFile -inkey $KeyFile -in $CertFile -passout pass:

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to convert certificate to PFX format."
    exit 1
}

# Step 5: Import certificate to Local Machine store
Write-Host "Importing certificate to Local Machine store..." -ForegroundColor Cyan
$ImportedCert = Import-PfxCertificate -FilePath $PfxFile `
    -CertStoreLocation Cert:\LocalMachine\My `
    -Exportable

# Step 6: Get the certificate thumbprint
$Thumbprint = $ImportedCert.Thumbprint
Write-Host "Certificate imported with thumbprint: $Thumbprint" -ForegroundColor Green

# Step 7: Verify certificate has required properties
$CertCheck = Get-ChildItem -Path Cert:\LocalMachine\My\$Thumbprint
if (-not $CertCheck.HasPrivateKey) {
    Write-Error "Certificate does not have a private key!"
    exit 1
}

Write-Host "Certificate details:" -ForegroundColor Cyan
Write-Host "  Subject: $($CertCheck.Subject)" -ForegroundColor Gray
Write-Host "  Issuer: $($CertCheck.Issuer)" -ForegroundColor Gray
Write-Host "  Valid From: $($CertCheck.NotBefore)" -ForegroundColor Gray
Write-Host "  Valid Until: $($CertCheck.NotAfter)" -ForegroundColor Gray
Write-Host "  Has Private Key: $($CertCheck.HasPrivateKey)" -ForegroundColor Gray

# Step 8: Grant Network Service read access to private key
Write-Host "Granting Network Service access to private key..." -ForegroundColor Cyan
try {
    $rsaCert = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($CertCheck)
    $fileName = $rsaCert.key.UniqueName
    $keyPath = "$env:ALLUSERSPROFILE\Microsoft\Crypto\Keys\$fileName"
    
    $permissions = Get-Acl -Path $keyPath
    $networkService = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::NetworkServiceSid, $null)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($networkService, 'Read', 'None', 'None', 'Allow')
    $permissions.AddAccessRule($rule)
    Set-Acl -Path $keyPath -AclObject $permissions
    
    Write-Host "Permissions granted successfully." -ForegroundColor Green
} catch {
    Write-Warning "Could not set Network Service permissions: $_"
    Write-Warning "You may need to set these manually if RDP connections fail."
}

# Step 9: Assign certificate to RDP listener
Write-Host "Assigning certificate to RDP listener..." -ForegroundColor Cyan
$TSPath = (Get-WmiObject -Class "Win32_TSGeneralSetting" `
    -Namespace root\cimv2\terminalservices `
    -Filter "TerminalName='RDP-Tcp'").__PATH

Set-WmiInstance -Path $TSPath -Argument @{SSLCertificateSHA1Hash=$Thumbprint}

# Step 10: Verify the certificate is applied
Write-Host "Verifying certificate assignment..." -ForegroundColor Cyan
$CurrentThumb = (Get-WmiObject -Class "Win32_TSGeneralSetting" `
    -Namespace root\cimv2\terminalservices `
    -Filter "TerminalName='RDP-Tcp'").SSLCertificateSHA1Hash

if ($CurrentThumb -eq $Thumbprint) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "SUCCESS!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Certificate successfully applied to RDS!" -ForegroundColor Green
    Write-Host "Hostname: $TailscaleHostname" -ForegroundColor Green
    Write-Host "Thumbprint: $CurrentThumb" -ForegroundColor Green
    Write-Host "`nYou can now connect via RDP using: $TailscaleHostname" -ForegroundColor Cyan
} else {
    Write-Error "Certificate assignment failed. Current thumbprint: $CurrentThumb"
    exit 1
}

# Optional: Clean up certificate files
Write-Host "`nCertificate files remain in current directory:" -ForegroundColor Yellow
Write-Host "  - $CertFile" -ForegroundColor Gray
Write-Host "  - $KeyFile" -ForegroundColor Gray
Write-Host "  - $PfxFile" -ForegroundColor Gray
Write-Host "You may want to securely delete these files." -ForegroundColor Yellow 
