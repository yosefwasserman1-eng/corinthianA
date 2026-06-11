# =====================================================================
# Corinthian Archive - Automated Immutable Setup Pipeline
# =====================================================================
$ErrorActionPreference = "Stop"

# Force UTF8 encoding for pipeline outputs
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "[*] Starting Automated Deployment (Corinthian Stack)" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# Helper function to expand environment variables in JSON strings
function Expand-EnvVars {
    param([string]$Text)
    return [regex]::Replace($Text, '\$\{([^}]+)\}', {
        param($match)
        $envVar = $match.Groups[1].Value
        $val = [Environment]::GetEnvironmentVariable($envVar)
        if ($null -eq $val) { return $match.Value } else { return $val }
    })
}

# ---------------------------------------------------------
# Phase 0: Load Environment Variables & Environment Cleanup
# ---------------------------------------------------------
Write-Host "[0/6] Loading network variables and secrets from .env..." -ForegroundColor Yellow
if (Test-Path ".\.env") {
    Get-Content ".\.env" | ForEach-Object {
        if ($_ -match '^(?!#)([^=]+)=(.*)$') {
            Set-Item -Path "Env:\$($matches[1])" -Value $matches[2]
        }
    }
} else {
    Write-Error "Error: .env file is missing! Cannot proceed."
    exit
}

if (-not (Test-Path ".\netfree-ca.crt")) {
    Write-Error "Error: netfree-ca.crt (NetFree Certificate) is missing! Cannot proceed."
    exit
}

Write-Host "Cleaning up legacy containers and orphaned volumes..." -ForegroundColor Gray
# Temporary lower error preference to ignore Docker stderr output
$tempErrPref = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"
docker compose down -v 2>&1 | Out-Null
$ErrorActionPreference = $tempErrPref

# ---------------------------------------------------------
# Phase 1: Local SSL/TLS Certificate Verification
# ---------------------------------------------------------
Write-Host "[1/6] Verifying local SSL/TLS certificates..." -ForegroundColor Yellow
if (-not (Test-Path ".\cert.pem") -or -not (Test-Path ".\key.pem")) {
    Write-Host "Certificates missing. Generating new local SSL certs via mkcert..." -ForegroundColor Gray
    try {
        # Temporary lower error preference to ignore mkcert stderr output
        $tempErrPref = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"

        mkcert -install 2>&1 | Out-Null
        mkcert -cert-file cert.pem -key-file key.pem $env:DOMAIN_ARCHIVE $env:DOMAIN_FORUM $env:DOMAIN_WIKI $env:DOMAIN_SSO $env:DOMAIN_CORE 2>&1 | Out-Null
        
        $ErrorActionPreference = $tempErrPref

        # Verify files were actually created
        if (Test-Path ".\cert.pem") {
            Write-Host "Certificates generated and trusted successfully!" -ForegroundColor Green
        } else {
            throw "mkcert executed but files were not created."
        }
    } catch { 
        $ErrorActionPreference = "Stop"
        Write-Error "Error: mkcert generation failed. Verify mkcert is installed and accessible in this terminal."
        exit 
    }
} else {
    Write-Host "Active SSL certificates found. Skipping generation." -ForegroundColor Green
}

# ---------------------------------------------------------
# Phase 2: Docker Cacheless Build & Orchestration
# ---------------------------------------------------------
Write-Host "[2/6] Building clean containers and initializing databases..." -ForegroundColor Yellow
docker compose build --no-cache

docker compose up -d postgres redis db nodebb-db
Write-Host "Waiting 15 seconds for database initialization and init.sql injection..." -ForegroundColor Gray
Start-Sleep -Seconds 15

Write-Host "Launching the remaining stack application layers..." -ForegroundColor Yellow
docker compose up -d
Write-Host "Waiting 20 seconds for core platforms (PHP/Node) to boot up..." -ForegroundColor Gray
Start-Sleep -Seconds 20

# ---------------------------------------------------------
# Phase 3: WordPress Automated Configuration & Dependency Injection
# ---------------------------------------------------------
Write-Host "[3/6] Configuring WordPress plugins and options..." -ForegroundColor Yellow
try {
    if (Test-Path ".\wordpress-plugins.json") {
        $rawWpJson = Get-Content ".\wordpress-plugins.json" -Raw
        $expandedWpJson = Expand-EnvVars -Text $rawWpJson
        $wpPlugins = $expandedWpJson | ConvertFrom-Json
        
        foreach ($plugin in $wpPlugins) {
            Write-Host "   Installing and activating: $($plugin.slug)" -ForegroundColor Gray
            docker compose exec -T -u www-data wordpress wp plugin install $($plugin.slug) --activate
            
            if ($null -ne $plugin.options) {
                foreach ($option in $plugin.options.PSObject.Properties) {
                    docker compose exec -T -u www-data wordpress wp option update $($option.Name) $($option.Value)
                }
            }
        }
        Write-Host "WordPress environment setup completed!" -ForegroundColor Green
    }
} catch { 
    Write-Warning "Warning: WordPress configuration failed. Ensure WP initial configuration is done in the browser." 
}

# ---------------------------------------------------------
# Phase 4: MediaWiki Dynamic Installation (Hybrid CLI Fallback)
# ---------------------------------------------------------
Write-Host "[4/6] Initializing MediaWiki extension compiler..." -ForegroundColor Yellow
try {
    $rawMwVer = ""
    # Try the modern CLI path first, fallback to legacy maintenance path
    try {
        $rawMwVer = (docker compose exec -T mediawiki php cli/showConfiguration.php --config wgVersion).Trim()
    } catch {
        $rawMwVer = (docker compose exec -T mediawiki php maintenance/showConfiguration.php --config wgVersion).Trim()
    }

    if ([string]::IsNullOrWhiteSpace($rawMwVer) -or $rawMwVer -match "Could not open") {
        throw "Could not detect MediaWiki version via CLI scripts."
    }

    $mwParts = $rawMwVer.Split('.')
    $dynamicMwVersion = "REL" + $mwParts[0] + "_" + $mwParts[1]
    Write-Host "   Detected MediaWiki core engine version: $rawMwVer (Branch target: $dynamicMwVersion)" -ForegroundColor DarkGray

    if (Test-Path ".\mediawiki-plugins.json") {
        $rawMwJson = Get-Content ".\mediawiki-plugins.json" -Raw
        $expandedMwJson = Expand-EnvVars -Text $rawMwJson
        $mwPlugins = $expandedMwJson | ConvertFrom-Json
        
        foreach ($plugin in $mwPlugins) {
            .\install-mediawiki-extension.ps1 -ExtensionName $($plugin.name) -MwVersion $dynamicMwVersion -SettingsList $($plugin.settings)
        }
        
        Write-Host "   Executing MediaWiki database schema updates (update.php)..." -ForegroundColor Gray
        try {
            docker compose exec -T mediawiki php cli/update.php --quick
        } catch {
            docker compose exec -T mediawiki php maintenance/update.php --quick
        }
        
        Write-Host "MediaWiki ecosystem configured successfully!" -ForegroundColor Green
    }
} catch { 
    Write-Warning "Warning: MediaWiki asset configuration failed. Reason: $_" 
}

# ---------------------------------------------------------
# Phase 5: NodeBB Plugin Activation & Asset Compilation
# ---------------------------------------------------------
Write-Host "[5/6] Activating and compiling NodeBB SSO module..." -ForegroundColor Yellow
try {
    Write-Host "   Registering local SSO plugin to core array..." -ForegroundColor Gray
    docker compose exec -T nodebb ./nodebb activate nodebb-plugin-sso-oauth
    
    Write-Host "   Compiling web assets (SCSS & HTML templates)..." -ForegroundColor Gray
    docker compose exec -T nodebb ./nodebb build
    
    Write-Host "   Executing soft restart on NodeBB service instance..." -ForegroundColor Gray
    docker compose exec -T nodebb ./nodebb restart
    Write-Host "NodeBB instance compiled successfully!" -ForegroundColor Green
} catch { 
    Write-Warning "Warning: NodeBB compilation failed. Try running './nodebb build' manually." 
}

# ---------------------------------------------------------
# Setup Completion Matrix
# ---------------------------------------------------------
Write-Host "`n[*] [6/6] Corinthian Infrastructure Stack is Online!" -ForegroundColor Green
Write-Host "----------------------------------------------------"
Write-Host "Central Archive   : https://$env:DOMAIN_ARCHIVE" -ForegroundColor Cyan
Write-Host "Community Forums  : https://$env:DOMAIN_FORUM" -ForegroundColor Cyan
Write-Host "Knowledge Wiki    : https://$env:DOMAIN_WIKI" -ForegroundColor Cyan
Write-Host "Identity Provider : https://$env:DOMAIN_SSO" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan