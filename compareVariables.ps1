param(
    [Parameter(Mandatory=$false)][string]$ServerA,
    [Parameter(Mandatory=$false)][string]$ServerB,
    [Parameter(Mandatory=$false)][string]$PortService
)

$listModuleFullFile = "./listModuleFull.txt"
$specialServices = @('','')
$ValidatedPortList = @()
$envPath = '/usr/servers/defaultServer/server.env'

function ReadEnv {
    param (
        $File
    )
    $outputVarsString = Get-Content -Path $File

    $isTheFirstVariable = $false
    $listModule = @()
    $dictModule = @{}
    # Use Get-Content to read the file line by line
    foreach ($line in $outputVarsString) {
        if ($line -match "-- (\w+)" -and !$isTheFirstVariable) { 
            $substring = $line.Substring(3)
            if ($substring -notin $listModule){
                $listModule += $substring
                $dictModule[$substring] = @()
                $currentModule = $substring
            } 
            $isTheFirstVariable = $true
        } elseif ($line -eq "--" -and $isTheFirstVariable) {
            $isTheFirstVariable = $false
        } 
        elseif ($isTheFirstVariable) {
            $dictModule[$currentModule] += $line.Trim()
        }

    }
     
    return $dictModule

}

function GetVariablesFromHost {
    param (
        $Username,
        $Hostname,
        $ModulePath
    )


    $sshCommand = "ssh ${Username}@${Hostname} 'cat ${ModulePath}'"

    $outputString = (Invoke-Expression -Command $sshCommand | Out-String).TrimEnd([Environment]::NewLine)
    # Extract variable names

    $variableNames = @($outputString -split "`n" | ForEach-Object {
        ($_ -split "=" | Select-Object -First 1).Trim()
    })    

    return $variableNames
}

function CompareVariableFromDiferentObject {
    param (
        $Object1,
        $Object2
    )
    # Compare 
    $comparisonResult = Compare-Object -ReferenceObject $Object2 -DifferenceObject $Object1

    # Filter out the elements that are unique to each list
    $missingVariables = $comparisonResult | Where-Object { $_.SideIndicator -eq '=>' } | Select-Object -ExpandProperty InputObject
	
	return $missingVariables
       
}

function CompareVariableFromDifferentHost {
    param (
        $User1,
        $Host1,
        $User2,
        $Host2,
        $ModulePath
    )

    $variableNamesHost1 = GetVariablesFromHost -Username $User1  -Hostname $Host1 -ModulePath $ModulePath
    $variableNamesHost2 = GetVariablesFromHost -Username $User2  -Hostname $Host2 -ModulePath $ModulePath

    $missingVariables = CompareVariableFromDiferentObject -Object1  $variableNamesHost1 -Object2 $variableNamesHost2
	
	if ($missingVariables.Count -eq 0) {
        Write-Host "Variable sufficiency" -ForegroundColor Green
    } else {
        Write-Host "Check ${ModulePath} on ${Host2}"
		Write-Host "The following variables are missing on ${Host2}" -ForegroundColor Cyan
        foreach ($variable in $missingVariables) {
            Write-Host $variable -ForegroundColor Yellow
        }
          
    }
}

function Get-Service-By-Port() {

    $Username = ''

    $Hostname = ""

    $sshCommand = "ssh ${Username}@${Hostname} 'ls ${servicePath}'"
    
    (Invoke-Expression -Command $sshCommand | Out-String).TrimEnd([Environment]::NewLine) | Out-File -FilePath $listModuleFullFile

}

if (Test-Path -Path $listModuleFullFile) {
    if ($isUpdateListModuleFull) {
        Get-Service-By-Port    
    }
} else {
    Write-Output "It seems to be the first time you're running this script. Please wait a moment to get the list of modules"
    Get-Service-By-Port
}

function Get-Validate-Port {
    param (
        $List,
	$ValidatedPortList
    )

    foreach ($ServiceAndPort in $List) {
        if ($ServiceAndPort -match '\.\d+$') {
            $ServiceAndPort = $ServiceAndPort -split '\.'
            $Port = $ServiceAndPort[-1]
            $ValidatedPortList += $Port
        }
    }

    return $ValidatedPortList

    
}

function Step-Run-Compare(){
    $ListServices = Get-Content -Path $listModuleFullFile
    $ValidatedPortList += Get-Validate-Port -List $ListServices -ValidatedPortList $ValidatedPortList 
    $ValidatedPortList += Get-Validate-Port -List $specialServices -ValidatedPortList $ValidatedPortList 
    
    if ( ! ($PortService -and $PortService -match '^\d+$') -or $ValidatedPortList -notcontains $PortService -or $PortService -eq "All" ) {
    
        Write-Warning "You need PortService parameter"
    
        Write-Host "Choose one of the ports to deploy modules correspondingly."
    
        foreach ($ServiceAndPort in $ListServices) {
            if ($ServiceAndPort -match '\.\d+$') {
                $ServiceAndPort = $ServiceAndPort -split '\.'
                $Port = $ServiceAndPort[-1]
                $ServiceName = $ServiceAndPort[1..($ServiceAndPort.Count - 2)] -join "."
                Set-Variable -Name $Port -Value $ServiceName
                Write-Host "    ${Port} --- ${ServiceName}"
            }
        }
    
        foreach ($ServiceAndPort in $specialServices) {
            if ($ServiceAndPort -match '\.\d+$') {
                $ServiceAndPort = $ServiceAndPort -split '\.'
                $Port = $ServiceAndPort[-1]
                $ServiceName = $ServiceAndPort[0..($ServiceAndPort.Count - 2)] -join "."
                Set-Variable -Name $Port -Value $ServiceName
                Write-Host "    ${Port} --- ${ServiceName}"
            }
        }
        
        $retryCount = 3
        for ($i = 1; $i -le $retryCount; $i++) {
            if ( ! ($PortService -and $PortService -match '^\d+$') -or $ValidatedPortList -notcontains $PortService) {
                $PortService = Read-Host "Please enter the port for your service"  
            }
    
            if ((! ($PortService -and $PortService -match '^\d+$') -or $ValidatedPortList -notcontains $PortService) -and ($retryCount - $i) -ne 0) {
                Write-Warning "Invalid port. Remaining $($retryCount - $i) attempts"
            }
        }
    }
    
    if ( ($PortService -and $PortService -match '^\d+$') -and $ValidatedPortList -contains $PortService -or $PortService -eq "All" ) {
        if ($PortService -eq "All"){
            $sourcePath = "/data"
            foreach ($ServiceAndPort in $ListServices) {
                if ($ServiceAndPort -match '\.\d+$') {
                    CompareVariableFromDifferentHost -User1 'hydro' -Host1 $ServerA -User2 'hydro' -Host2 $ServerB -ModulePath "${sourcePath}${ServiceAndPort}${envPath}"
                }
            }
            $sourcePath = "/data/"
            foreach ($ServiceAndPort in $specialServices) {
                if ($ServiceAndPort -match '\.\d+$') {
                    CompareVariableFromDifferentHost -User1 'hydro' -Host1 $ServerA -User2 'hydro' -Host2 $ServerB -ModulePath "${sourcePath}${ServiceAndPort}${envPath}"
                }
            }
        } else {
            switch ($PortService) {
                '9020' {
                    $sourcePath = '/data'
                    $moduleName = "$(Get-Variable -Name $PortService -ValueOnly).${PortService}"
                }
                '9330' {
                    $sourcePath = '/data'
                    $moduleName = "$(Get-Variable -Name $PortService -ValueOnly).${PortService}"
                
                }
                default {
                    $sourcePath = '/data'
                    $moduleName = "$(Get-Variable -Name $PortService -ValueOnly).${PortService}"
        
                }
            }    
            CompareVariableFromDifferentHost -User1 '' -Host1 $ServerA -User2 '' -Host2 $ServerB -ModulePath "${sourcePath}/${moduleName}${envPath}"
        } 
    
    } else {
        Write-Error "Please select a port from the list above to deploy your service."
    }
    
}

if ( $ServerA -and $ServerB) {
    Step-Run-Compare
} else {
    Write-Error "Please provide variables for ServerA and ServerB."
}
