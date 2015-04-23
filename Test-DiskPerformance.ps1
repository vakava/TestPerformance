<#

.SYNOPSIS

This is very accurate short description of this wall of code.


.DESCRIPTION

Long description


.PARAMETER SqlioPath
    Param1 description


.PARAMETER TestDuration
    Approximate time of test in seconds. Do get accurate results it should be at least 600 seconds.

Param2 description

.PARAMETER NumberOfPhases
    Phase is one run of sqlio for each parameter set. Results are an average from numberOfPhases runs.

.EXAMPLE
Test-DiskPerformance.ps1 -SqlioPath D:\SQLIO -TestFilePath C:\Test -TestFileSize 1GB -PhaseDuration 1 -IOSize 4 -OutIO 1 -NumberOfPhases 1 -Type random,sequential -Direction Write,Read

To test script, sqlio path is specified, phase duration is set to shortest possible value, there is just one IOSize, one number of OutIO, one phase per each test

.EXAMPLE 

Example2

.NOTES

#>

Param (
    [Parameter(Mandatory=$False)]        
    [ValidateScript({Test-Path $_ -PathType Container})]        
    [string]
    $SqlioPath ='.',

    [parameter(mandatory=$False)] 
    $TestFilePath = '.',

    [parameter(mandatory=$False)]
    [ValidateRange(1MB,400GB)]
    [int64]
    $TestFileSize = 1GB,

    [Parameter(Mandatory=$False)]
    [ValidateRange(1,16)]
    [int]
    $NumberOfThreads = (Get-WmiObject win32_computersystem | select -ExpandProperty NumberOfLogicalProcessors),

    [Parameter(Mandatory=$False)]
    [int]
    $PhaseDuration = 30,

    [Parameter(Mandatory=$False)]
    [string]
    $ResultsPath = '.',

    [Parameter(Mandatory=$False)]
    [string]
    $ResultsFileName = "Test-DiskPerformance-Results-$(Get-Date -Format MM-dd-yyyy_hh-mm-ss)",

    [Parameter(Mandatory=$False)]
    [string[]]
    $IOSize = ('4','8','64','512'),

    [Parameter(Mandatory=$False)]
    [String[]]
    $OutIO = ('1','2','4','8','16','32','64'),

    [Parameter(Mandatory=$False)]
    [int]
    $NumberOfPhases = 3,

    [Parameter(Mandatory=$False)]
    [ValidateSet('random','sequential')]
    [string[]]
    $Type = ('random','sequential'),

    [Parameter(Mandatory=$False)]
    [ValidateSet('Read','Write')]
    [string[]]
    $Direction = ('Read','Write')

)

BEGIN {
    # check sqlio.exe path
    if (-NOT (Test-Path "$SqlioPath\sqlio.exe" -PathType Leaf)) {
        Write-Error "sqlio.exe not found in $SqlioPath"
        Break    
    } else {
        Write-Output "Successfully found sqlio.exe at $SqlioPath "
    }
    # check test duration
    if ($PhaseDuration -lt 30){
        Write-Warning "Test with phase duration less then 30 seconds will most likely give wrong results"
    }
    # check testfilesize
    if ($TestFileSize -lt 10GB) {
        Write-Warning "Using testfile size smaller then 10GB will most likely give wrong results"
    }
    # check testfile path, create file if missing
    if (-NOT (Test-Path "$TestFilePath\TestFile.DAT" -PathType Leaf)) {
        Write-Output "Test file not found, creating test file in $TestFilePath"
        try {
            FSUTIL.EXE file createnew "$TestFilePath\TestFile.DAT" ($TestFileSize)
            FSUTIL.EXE file setvaliddata "$TestFilePath\TestFile.DAT" ($TestFileSize)
            Write-Output "Created test file successfully at $TestFilePath"
        } catch {
            Write-Error "Something went wrong with creating test file."
            Break
        }
    } else {
        Write-Output "Successfully found test file at $TestFilePath "
    }
    # adjust number of cores
    if ($NumberOfThreads -gt 16) {        
        Write-Warning "Limiting number of threads used during test from $NumberOfThreads to max value of 16"
        $NumberOfThreads = 16
    }

    # get names of columns from performance counters, to create extra NoteProperties for PartialResults psobject
    $CPUColumns = (Get-Counter '\Processor Information(*)\% Processor Time').CounterSamples.InstanceName | Sort-Object

    # check ResultsFilePath
    if (-NOT (Test-Path "$ResultsPath" -PathType Container)){
        Write-Error "Can't find path for ResultsTestFile"
        Break
    } else {
        Write-Output "Successfully validated path for ResultsTestFile"
    }

    # prepare variables
    $phaseNo = 1
    $t = "-t$NumberOfThreads"
    $d = "-s$PhaseDuration"
    $AllResult = @()
    
    # variabls for displaying status of test
    $SumOfPhases = $NumberOfPhases*$Type.Length*$OutIO.Length*$IOSize.Length*$Direction.Length

} PROCESS {
    Write-Output "Starting testing phase"
    
    # loop through direction of IO
    for($DirectionNo=0;$DirectionNo -lt $Direction.Count;$DirectionNo++){
        # get first letter from Read or Write word
        $dir = "-k$($Direction[$DirectionNo][0])"
        # loop through types of tests
        for($TypeNo=0;$TypeNo -lt $Type.Length;$TypeNo++){
            # loop through size of 
            for($IOSizeNo=0;$IOSizeNo -lt $IOSize.Length;$IOSizeNo++){
                $f = "-f$($Type[$TypeNo])";

                # loop through number of OutIOs
                for($OutIONo=0;$OutIONo -lt $OutIO.Length;$OutIONo++){
                    $o = "-o$($OutIO[$OutIONo])"
                    $b = "-b$($IOSize[$IOSizeNo])"
                    $SumIops = 0
                    $SumMbs = 0
                    $SumLatency = 0

                    # loop numberOfPhases times to get average results
                    for($i=1;$i -le $NumberOfPhases;$i++){
                        # displaying phase number
                        Write-Host Phase $phaseNo of $SumOfPhases
                        # start get-counters for CPU usage as job
                        Start-Job {
                            # get average CPU usage during testing, values in same order as columns names in NoteProperties                       
                            (Get-Counter '\Processor Information(*)\% Processor Time' -SampleInterval $args[0]).countersamples | `                            
                            Select-Object -Property InstanceName,CookedValue |`
                            Sort-Object -Property InstanceName | `
                            Select-Object -ExpandProperty Cookedvalue
                        } -ArgumentList $PhaseDuration -Name PerfCounters | Out-Null
                        $Result = & $SqlioPath\sqlio.exe $d $dir $f $b $o $t -LS -BN "$TestFilePath\TestFile.DAT"
                    
                        Start-Sleep -Seconds 1 -Verbose
                        Wait-Job -Name PerfCounters | Out-Null
                        $CPUValues = Receive-Job -Name PerfCounters
                        Remove-Job -Name PerfCounters

                        $iops = $Result.Split("`n")[10].Split(':')[1].Trim() 
                        $mbs = $Result.Split("`n")[11].Split(':')[1].Trim() 
                        $latency = $Result.Split("`n")[14].Split(':')[1].Trim()
                        $SeqRnd = $Result.Split("`n")[14].Split(':')[1].Trim()
        
                        $SumIops += $iops
                        $SumMbs += $mbs
                        $SumLatency += $latency

                        $phaseNo++
                    }
                    $hash = [ordered]@{
                        Target = $("$TestFilePath\$TestFileName")
                        Direction = $($Direction[$DirectionNo])
                        Type = $($Type[$TypeNo])
                        SizeIOKBytes = $($IOSize[$IOSizeNo])
                        OutIOs = $($OutIO[$OutIONo])
                        IOPS = [math]::Floor($($SumIops/$numberOfPhases))
                        MBSec = $($SumMbs/$numberOfPhases)
                        LatencyMS = $($SumLatency/$numberOfPhases)                                        
                    }
                    $PartialResult = New-Object -TypeName psobject -property $hash
                    # adding performance counters to NoteProperties of the object
                    for($CPUValueIndex=0;$CPUValueIndex -lt $CPUColumns.Count;$CPUValueIndex++){
                        Add-Member -MemberType NoteProperty -InputObject $PartialResult `
                        -Name ("CPU"+$CPUColumns[$CPUValueIndex]) -Value ("{0:N2}" -f $($CPUValues[$CPUValueIndex]))
                    }
                    $AllResult += $PartialResult
                }
            }
         }
     }
} END {
    $TestFileSizeMB = $TestFileSize/1MB
    $AllResult | Export-Csv -Path "$ResultsPath\$ResultsFileName.csv" -NoTypeInformation
    Write-Output "Test ended on test file in $TestFilePath ($TestFileSizeMB MB) with results saved into $ResultsPath\$ResultsFileName"
}
