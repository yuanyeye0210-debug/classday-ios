# Run pure Kotlin core tests from existing Gradle caches without an Android SDK.
# No downloads, signing files, Android build configuration or system settings are changed.
$ErrorActionPreference = 'Stop'
$cacheRoot = Join-Path $env:USERPROFILE '.gradle/caches/modules-2/files-2.1'
function Find-Jar($group, $artifact, $version) {
    $jar = Get-ChildItem -LiteralPath "$cacheRoot/$group/$artifact/$version" -Recurse -Filter '*.jar' | Select-Object -First 1
    if (-not $jar) { throw "Missing cached dependency: $group/$artifact/$version" }
    $jar.FullName
}
$compilerPath = @(
    (Find-Jar 'org.jetbrains.kotlin' 'kotlin-compiler-embeddable' '2.2.21'),
    (Find-Jar 'org.jetbrains.kotlin' 'kotlin-stdlib' '2.2.21'),
    (Find-Jar 'org.jetbrains.kotlin' 'kotlin-script-runtime' '2.2.21'),
    (Find-Jar 'org.jetbrains.kotlin' 'kotlin-reflect' '1.6.10'),
    (Find-Jar 'org.jetbrains.kotlinx' 'kotlinx-coroutines-core-jvm' '1.8.0'),
    (Find-Jar 'org.jetbrains' 'annotations' '13.0')
) -join ';'
$testPath = @(
    (Find-Jar 'org.jetbrains.kotlin' 'kotlin-stdlib' '2.2.21'),
    (Find-Jar 'org.jetbrains.kotlinx' 'kotlinx-serialization-json-jvm' '1.9.0'),
    (Find-Jar 'org.jetbrains.kotlinx' 'kotlinx-serialization-core-jvm' '1.9.0'),
    (Find-Jar 'junit' 'junit' '4.13.2'),
    (Find-Jar 'org.hamcrest' 'hamcrest-core' '1.3'),
    (Find-Jar 'org.jetbrains' 'annotations' '13.0'),
    (Find-Jar 'org.json' 'json' '20240303')
) -join ';'
$plugin = Find-Jar 'org.jetbrains.kotlin' 'kotlin-serialization-compiler-plugin-embeddable' '2.2.21'
$androidRoot = Split-Path $PSScriptRoot -Parent
$outputDir = Join-Path $env:TEMP ('classday-core-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $outputDir | Out-Null
$coreFiles = (Get-ChildItem "$androidRoot/app/src/main/java/com/classday/app/core" -Filter '*.kt').FullName
$testNames = @('MailImportTest', 'WordImportTest', 'ExcelImportTest', 'GridDragTest', 'PdfImportPolicyTest', 'FinalScorePredictionTest', 'TodayOverviewTest', 'CameraCaptureFilesTest', 'GradeScoreEditorTest', 'ScheduleLogicTest', 'ClassroomDndPlanTest', 'StudyEntryEditorTest', 'UpdateIntegrityTest', 'MapLinksTest', 'UpdatePackageStagerTest', 'CourseReminderTest', 'ExamCopyTest', 'ExamTimelineTest', 'WeekDaySelectionTest')
$testFiles = $testNames | ForEach-Object { "$androidRoot/app/src/test/java/com/classday/app/$_.kt" }
& java -cp $compilerPath org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -jvm-target 17 -classpath $testPath "-Xplugin=$plugin" -d $outputDir @coreFiles @testFiles
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$testClasses = $testNames | ForEach-Object { "com.classday.app.$_" }
& java -cp "$outputDir;$testPath" org.junit.runner.JUnitCore @testClasses
exit $LASTEXITCODE
