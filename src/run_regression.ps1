param(
    [string]$VivadoBin = 'D:\vivado\Vivado\2024.1\bin',
    [string]$Tclsh = 'tclsh.exe',
    [string[]]$Tests = @('tb_control_regression','tb_feedback_regression','tb_adc_capture_regression','tb_vio_uart_regression','tb_pid_delay_regression','tb_dac_regression','tb_capture_phase_regression')
)
$ErrorActionPreference = 'Stop'
$projectDir = $PSScriptRoot
$rtlDir = Join-Path $projectDir 'power-kicker-fast-feedback-v1.srcs\sources_1\new'
$testDir = Join-Path $projectDir 'tests'
$runDir = Join-Path $projectDir ('verification\sim_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $runDir | Out-Null
$sourceMap = @{
    tb_capture_phase_regression = @('capture_phase_status')
    tb_control_regression = @('control')
    tb_feedback_regression = @('pid_core_signed','pd_pid_feedback')
    tb_adc_capture_regression = @('reset_sync','pd_adc_capture')
    tb_vio_uart_regression = @('reset_sync','control','pid_core_signed','pd_pid_feedback','uart_rx','uart_tx','uart_power_kick_params','capture_phase_status','top_power_kicker')
    tb_pid_delay_regression = @('reset_sync','control','pid_core_signed','pd_pid_feedback','uart_rx','uart_tx','uart_power_kick_params','capture_phase_status','top_power_kicker')
    tb_dac_regression = @('test_ad9122','key_filter')
}
$results = @()
foreach ($test in $Tests) {
    if (-not $sourceMap.ContainsKey($test)) { throw "Unknown test $test" }
    $testRun = Join-Path $runDir $test
    New-Item -ItemType Directory -Path $testRun | Out-Null
    Push-Location $testRun
    try {
        $sources = @($sourceMap[$test] | ForEach-Object { Join-Path $rtlDir ($_.ToString() + '.v') })
        if ($test -in @('tb_vio_uart_regression','tb_pid_delay_regression')) { $sources += Join-Path $testDir 'vio_hardware_mocks.sv' }
        if ($test -eq 'tb_dac_regression') {
            $sources += Join-Path $testDir 'ila_dac_mock.sv'
            $sources += Join-Path $VivadoBin '..\data\verilog\src\glbl.v'
        }
        $sources += Join-Path $testDir ($test + '.sv')
        & (Join-Path $VivadoBin 'xvlog.bat') -sv @sources
        if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $test" }
        $elabArgs = @($test, '-s', $test, '-debug', 'typical')
        if ($test -eq 'tb_dac_regression') { $elabArgs += @('glbl','-L','unisims_ver') }
        & (Join-Path $VivadoBin 'xelab.bat') @elabArgs
        if ($LASTEXITCODE -ne 0) { throw "Elaboration failed: $test" }
        & (Join-Path $VivadoBin 'xsim.bat') $test -runall -onerror quit -onfinish quit -log simulation.log
        if ($LASTEXITCODE -ne 0) { throw "Simulation failed: $test" }
        $log = Get-Content -LiteralPath 'simulation.log' -Raw
        # $fatal may not propagate to the launcher exit code: require a sentinel.
        if ($log -notmatch ('PASS:\s*' + [regex]::Escape($test)) -or $log -match '(?im)^\s*(Fatal:|FAIL:)') {
            throw "Self-check failed or did not finish: $test; see $testRun\simulation.log"
        }
        $results += "PASS: $test"
    } finally { Pop-Location }
}
foreach ($tclTest in @('test_io_timing_constraints','test_vio_helpers')) {
    $testPath = (Join-Path $testDir ($tclTest + '.tcl')).Replace('\','/')
    $output = & $Tclsh $testPath 2>&1
    $output | Out-File -LiteralPath (Join-Path $runDir ($tclTest + '.log')) -Encoding UTF8
    $output
    if ($LASTEXITCODE -ne 0 -or ($output -join "`n") -notmatch ('PASS:\s*' + $tclTest)) {
        throw "Tcl regression failed: $tclTest"
    }
    $results += "PASS: $tclTest"
}
$results | Out-File -LiteralPath (Join-Path $runDir 'summary.txt') -Encoding UTF8
$results
"REGRESSION=PASS ($($results.Count) suites)"
"LOG_DIRECTORY=$runDir"

