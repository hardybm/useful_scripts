# Tailscale RDS Certificate Updater

Automatically update Windows Remote Desktop Services (RDS) certificates with Tailscale-generated Let's Encrypt certificates.

## Overview

This PowerShell script automates the process of:
1. Detecting your Tailscale hostname
2. Generating a Let's Encrypt certificate via Tailscale
3. Converting and importing the certificate to Windows
4. Configuring RDS to use the new certificate

No more certificate warnings when connecting to your Windows machine via Remote Desktop over Tailscale!

## Prerequisites

### Required
- **Windows 10/11** or **Windows Server 2016+**
- **Tailscale client** installed and running
- **Administrator privileges**
- **OpenSSL** for certificate conversion

### Tailscale Configuration
In your [Tailscale Admin Console](https://login.tailscale.com/admin):
1. Navigate to **DNS** settings
2. Enable **MagicDNS**
3. Enable **HTTPS Certificates**

### Install OpenSSL

```powershell
# Using winget (recommended)
winget install OpenSSL.Light

# Or using Chocolatey
choco install openssl.light
```

## Installation

1. Clone this repository or download the script:

2. Ensure you can run PowerShell scripts:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Usage

### Basic Usage

Run the script in an **elevated PowerShell** session:

```powershell
.\Update-RDSTailscaleCert.ps1
```

The script will:
- ✅ Automatically detect your Tailscale hostname
- ✅ Generate a new certificate
- ✅ Import it to the Windows certificate store
- ✅ Configure RDS to use it
- ✅ Verify the configuration

### Expected Output
