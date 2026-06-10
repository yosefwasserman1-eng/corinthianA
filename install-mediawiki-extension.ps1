param (
    [Parameter(Mandatory=$true)][string]$ExtensionName,
    [Parameter(Mandatory=$true)][string]$MwVersion,
    [Parameter(Mandatory=$false)][array]$SettingsList = @()
)

$localSettingsPath = ".\mediawiki\LocalSettings.php"
$extLine = "wfLoadExtension( '$ExtensionName' );"

Write-Host "   📥 מוריד ומחלץ את: $ExtensionName (עבור ענף $MwVersion)..." -ForegroundColor Gray
$url = "https://extdist.wmflabs.org/dist/extensions/$ExtensionName-$MwVersion-latest.tar.gz"

try {
    Invoke-WebRequest -Uri $url -OutFile "$ExtensionName.tar.gz"
    tar -xzf "$ExtensionName.tar.gz" -C .\mediawiki\extensions\
    Remove-Item "$ExtensionName.tar.gz"
} catch {
    Write-Warning "   ⚠️ נכשלה הורדת התוסף $ExtensionName. ודא שהוא תואם לגרסה."
    exit
}

# רישום התוסף והזרקת הגדרות למניעת כפילויות
if (Test-Path $localSettingsPath) {
    if (-not (Select-String -Path $localSettingsPath -Pattern [regex]::Escape($extLine) -Quiet)) {
        Add-Content -Path $localSettingsPath -Value "`n$extLine"
        Write-Host "   ✅ נרשם בהצלחה ב-LocalSettings.php" -ForegroundColor Green
    } else {
        Write-Host "   ℹ️ התוסף כבר רשום, מדלג על רישום הליבה." -ForegroundColor DarkGray
    }

    # הזרקת הגדרות התוסף (לאחר שהסקריפט הראשי כבר החליף את משתני הסביבה בהן)
    if ($SettingsList.Count -gt 0) {
        Add-Content -Path $localSettingsPath -Value "`n# Settings for $ExtensionName"
        foreach ($setting in $SettingsList) {
            if (-not (Select-String -Path $localSettingsPath -Pattern [regex]::Escape($setting) -Quiet)) {
                Add-Content -Path $localSettingsPath -Value $setting
                Write-Host "   ⚙️ הוזרקה הגדרה: $setting" -ForegroundColor DarkCyan
            }
        }
    }
} else {
    Write-Warning "   ⚠️ הקובץ LocalSettings.php לא נמצא. מדלג על רישום ההגדרות."
}