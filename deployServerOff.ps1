param(
    [Parameter(Mandatory=$false)][string[]]$OFFServer= @('List-IP-Address-Your-Server'),
    [Parameter(Mandatory=$false)][string[]]$ActiveServer= @('List-IP-Address-Your-Server'),
    [Parameter(Mandatory=$false)][string]$PortService,
    [Parameter(Mandatory=$true)][string]$BPM,
    [Parameter(Mandatory=$false)][string[]]$MultiplePortServices,
    [Parameter(Mandatory=$false)][ValidateSet('Y','YES')][string]$isUpdateListModuleFull,
    [Parameter()][string]$OFFUser = 'Your-User',
    [Parameter()][string]$ActiveUser = 'Your-User'
)

$homePath = "/Your/Home/Path"
$scriptDeploy = "${homePath}/runUpdateModuleOFF_ver2.sh"
$scriptEdgeManager = "${homePath}/edge_manager.sh"
$scriptServiceManager = "${homePath}/service_manager.sh"
$servicePath = "/Your/Service/Path/"

function Step-Pre-Deploy {
    param (
        $Username,
        $Hostname,
        $dirAllNeededFilesDeployed
    )

    
    $dirWarDeploy="${dirAllNeededFilesDeployed}/dropins"
	$fileServerUpdate="${dirAllNeededFilesDeployed}/Server_off_vars.txt"

    if (Test-Path -Path $dirAllNeededFilesDeployed) {
        if (-not (Test-Path $dirWarDeploy)) {
            New-Item -ItemType Directory -Path $dirWarDeploy -Force
            Write-Error "Copy War/Jar file to $dirWarDeploy first "
			exit
        } else {
			Write-Host "Copying...."
            Write-Host "scp -r $dirAllNeededFilesDeployed ${Username}@${Hostname}:${homePath}"
        }
    } else {
        New-Item -ItemType Directory -Path $dirAllNeededFilesDeployed -Force
		New-Item -ItemType File -Path $fileServerUpdate -Force
        Write-Error "Not found $dirAllNeededFilesDeployed"
		exit
    }

}

function Step-Backup {
    param (
        $Username,
        $Hostname,
        $dirAllNeededFilesDeployed
    )

    $sshCommand = "ssh ${Username}@${Hostname} 'sh $scriptDeploy back_up $dirAllNeededFilesDeployed'"

    Invoke-Expression -Command $sshCommand
    
}

function Step-Deploy {
    param (
        $Username,
        $Hostname,
        $dirAllNeededFilesDeployed
    )

    $sshCommand = "ssh ${Username}@${Hostname} 'sh $scriptDeploy deploy $dirAllNeededFilesDeployed'"

    Invoke-Expression -Command $sshCommand
    
}

function Get-Service-By-Port() {

    $Username = $OFFUser

    $Hostname = "Your Server's IP Address"

    $sshCommand = "ssh ${Username}@${Hostname} 'ls ${servicePath}'"
    
    (Invoke-Expression -Command $sshCommand | Out-String).TrimEnd([Environment]::NewLine) | Out-File -FilePath "listModuleFull.txt"

}

function Step-Stop-Edge {
    param (
        $Username,
        $Hostname
    )

    $sshCommand = "ssh ${Username}@${Hostname} 'sh $scriptEdgeManager stop'"

    Invoke-Expression -Command $sshCommand
    
}

function Step-Start-Edge {
    param (
        $Username,
        $Hostname
    )

    $sshCommand = "ssh ${Username}@${Hostname} 'sh $scriptEdgeManager start'"

    Invoke-Expression -Command $sshCommand
    
}

function Step-Stop-Service {
    param (
        $Username,
        $Hostname,
        [Parameter(Mandatory=$true)][string]$PortService
    )

    $sshCommand = "ssh ${Username}@${Hostname} 'sh $scriptServiceManager stop $PortService'"

    Invoke-Expression -Command $sshCommand
    
}

function Step-Start-Service {
    param (
        $Username,
        $Hostname,
        [Parameter(Mandatory=$true)][string]$PortService
    )

    $sshCommand = "ssh ${Username}@${Hostname} 'sh $scriptServiceManager start $PortService'"

    Invoke-Expression -Command $sshCommand
    
}


$listModuleFullFile = "./listModuleFull.txt"

if (Test-Path -Path $listModuleFullFile) {
    if ($isUpdateListModuleFull) {
        Get-Service-By-Port    
    }
} else {
    Write-Output "It seems to be the first time you're running this script. Please wait a moment to get the list of modules"
    Get-Service-By-Port
}

$ValidatedPortList = @()

$outputVarsString = Get-Content -Path $listModuleFullFile

foreach ($ServiceAndPort in $outputVarsString) {
    if ($ServiceAndPort -match '\.\d+$') {
        $ServiceAndPort = $ServiceAndPort -split '\.'
        $Port = $ServiceAndPort[-1]
        $ValidatedPortList += $Port
    }
}

function Step-Validate-Port-Service {
    param (
        $PortService
    )

    if ( ! ($PortService -and $PortService -match '^\d+$') -or $ValidatedPortList -notcontains $PortService) {
        return $true
    } 

    return $false
}


function Step-Validate-Multiple-Port-Services {
    param (
        $MultiplePortServices
    )
    $isOK = $false
    foreach ($PortService in $MultiplePortServices) {
        if (-not (Step-Validate-Port-Service -PortService $PortService)) {
            $isOK = $true
        } else {
            return $false        
        } 
  
    }
    return $isOK

}

function Step-Delivery {
    param (
        $Username,
        $ListServer,
        [Parameter(Mandatory=$true)][string]$PortService
    )
    
    $dirAllNeededFilesDeployed="${PortService}_deploy_today_${BPM}"
    
    foreach ($Server in $ListServer) {
        Step-Pre-Deploy -Username $Username -Hostname $Server -dirAllNeededFilesDeployed $dirAllNeededFilesDeployed
        Step-Backup -Username $Username -Hostname $Server -dirAllNeededFilesDeployed $dirAllNeededFilesDeployed
        Step-Deploy -Username $Username -Hostname $Server -dirAllNeededFilesDeployed $dirAllNeededFilesDeployed
    }       
}

if (Step-Validate-Multiple-Port-Services -MultiplePortServices $MultiplePortServices) {
    Write-Host "Use MultiplePortServices"
    foreach ($PortService in $MultiplePortServices) {
        Step-Delivery -Username $OFFUser -ListServer $OFFServer -PortService $PortService
    }
} else {
    Write-Warning "Invalid MultiplePortServices. Use PortServices"
    if (Step-Validate-Port-Service -PortService $PortService) {
        if ( ! ($PortService -and $PortService -match '^\d+$') -or $ValidatedPortList -notcontains $PortService) {

            Write-Warning "You need PortService parameter"

            Write-Host "Choose one of the ports to deploy modules correspondingly."

            foreach ($ServiceAndPort in $outputVarsString) {
                if ($ServiceAndPort -match '\.\d+$') {
                    $ServiceAndPort = $ServiceAndPort -split '\.'
                    $Port = $ServiceAndPort[-1]
                    $ServiceName = $ServiceAndPort[1..($ServiceAndPort.Count - 2)] -join "-"
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
    } 

    if (-not (Step-Validate-Port-Service -PortService $PortService)) {

        Write-Host "Your Service will be deployed in a few minutes" -ForegroundColor Green
        
        Step-Delivery -Username $OFFUser -ListServer $OFFServer -PortService $PortService

        Write-Host "Congratulations. Your Service has been deployed." -ForegroundColor Green

    } else {

        Write-Error "Please select a port from the list above to deploy your service."

    }

}
