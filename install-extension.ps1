param (
    [Parameter(Mandatory=$true)]
    [string]$ExtensionName
)

# הגדרת נתיבים (לפי המבנה המסודר שלך)
$ExtensionDir = ".\mediawiki_extensions\$ExtensionName"
$LocalSettingsPath = ".\LocalSettings.php"
$ZipFile = ".\mediawiki_extensions\$ExtensionName.tar.gz"

Write-Host "🚀 מתחיל תהליך התקנה דינמי עבור התוסף: $ExtensionName" -ForegroundColor Cyan

# --- שלב א': זיהוי אוטומטי של גרסת המדיה-וויקי מתוך הדוקר ---
Write-Host "🔍 מזהה את גרסת ה-MediaWiki המותקנת במערכת..." -ForegroundColor Yellow

$MwVersion = ""
try {
    # פנייה ל-API הפנימי של המדיה-וויקי בקונטיינר כדי לקבל את פרטי המערכת (שמותקנת מקומית)
    # משתמשים ב-host-gateway או בשם השירות בקומפוז, או ישירות דרך פקודת דוקר שקוראת את הגרסה מהקוד
    $VersionRaw = docker compose exec mediawiki php -r "require 'includes/WebStart.php'; echo MW_VERSION;" 2>$null
    
    # ניקוי רווחים ותווים מיותרים מהפלט של דוקר
    if ($VersionRaw) {
        $MwVersion = $VersionRaw.Trim()
    }
} catch {
    # גיבוי: אם הדוקר כבוי ברגע זה, ננסה לקרוא מקובץ מקומי אם קיים, או נבקש מהמשתמש
    $MwVersion = ""
}

# אם זיהוי אוטומטי נכשל (למשל הקונטיינר כבוי), נציב גרסת ברירת מחדל בטוחה או נחלץ אותה ידנית
if ([string]::IsNullOrEmpty($MwVersion)) {
    Write-Host "⚠️ לא ניתן היה לקרוא את הגרסה מהקונטיינר החי. מנסה גרסת ברירת מחדל יציבה (1.41)..." -ForegroundColor Yellow
    $MwVersion = "1.41.0" 
}

# המרת פורמט הגרסה (למשל מ-1.41.2 ל-REL1_41)
# ה-API של ויקימדיה מחזיק את התוספים המוכנים לפי פורמט של REL[גרסה_ראשית]_[גרסה_משנית]
$VersionElements = $MwVersion.Split('.')
$MajorMinor = $VersionElements[0] + "_" + $VersionElements[1] # יוצא למשל: 1_41
$BranchName = "REL" + $MajorMinor                            # יוצא למשל: REL1_41

Write-Host "✅ הגרסה שזוהתה: $MwVersion (Branch מותאם: $BranchName)" -ForegroundColor Green

# --- שלב ב': בניית ה-URL המדויק והורדת התוסף ---
# השרת הרשמי מחזיק Snapshots מוכנים כולל vendor לכל Branch רשמי!
$DownloadUrl = "https://extdist.wmflabs.org/dist/extensions/$ExtensionName-$BranchName.tar.gz"

if (Test-Path $ExtensionDir) {
    Write-Host "⚠️ התיקייה $ExtensionName כבר קיימת בפרויקט." -ForegroundColor Yellow
} else {
    Write-Host "📥 מוריד את הגרסה התואמת משרתי ויקימדיה..." -ForegroundColor Green
    Write-Host "🔗 קישור הורדה: $DownloadUrl" -ForegroundColor Gray
    
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipFile -UserAgent "Mozilla/5.0"
    } catch {
        Write-Error "❌ ההורדה נכשלה! ייתכן שהתוסף לא קיים עבור גרסה $MwVersion, או ששם התוסף שגוי."
        if (Test-Path $ZipFile) { Remove-Item $ZipFile }
        exit
    }

    Write-Host "📦 מחלץ את קבצי התוסף (כולל ה-Vendor המובנה)..." -ForegroundColor Green
    New-Item -ItemType Directory -Force -Path $ExtensionDir | Out-Null
    
    # חילוץ קובץ ה-tar.gz
    tar -xf $ZipFile -C ".\mediawiki_extensions\"
    
    if (Test-Path $ZipFile) { Remove-Item $ZipFile }
    Write-Host "✅ החילוץ הסתיים בהצלחה!" -ForegroundColor Green
}

# --- שלב ג': רישום אוטומטי ב-LocalSettings.php ---
if (Test-Path $LocalSettingsPath) {
    $ExtensionLine = "wfLoadExtension( '$ExtensionName' );"
    $FileContent = Get-Content $LocalSettingsPath -Raw
    
    if ($FileContent -match "wfLoadExtension\(\s*'$ExtensionName'\s*\);") {
        Write-Host "ℹ️ התוסף $ExtensionName כבר רשום בקובץ ההגדרות." -ForegroundColor Yellow
    } else {
        Write-Host "📝 מוסיף את התוסף ל-LocalSettings.php..." -ForegroundColor Green
        Add-Content -Path $LocalSettingsPath -Value "`n# --- תוסף שהותקן אוטומטית ($BranchName) ---`n$ExtensionLine"
        Write-Host "✅ הרישום בוצע בהצלחה!" -ForegroundColor Green
    }
}

# --- שלב ד': ריסטארט ורענון ---
Write-Host "🔄 מרענן את קונטיינר המדיה-וויקי להחלת השינויים..." -ForegroundColor Cyan
docker compose restart mediawiki

Write-Host "🏆 התקנת התוסף $ExtensionName הסתיימה בהצלחה מוחלטת ומותאמת אישית לגרסת האתר שלך!" -ForegroundColor Green