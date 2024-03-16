param(
    [Parameter(Mandatory=$false)][string]$ServerA,
    [Parameter(Mandatory=$false)][string]$ServerB,
    [Parameter(Mandatory=$false)][string]$PortService
)

$AllServers = @('','','')   
$listModuleFullFile = "./listModuleFull.txt"
$servicePath = "/data"
$specialServices = @('','')
$ValidatedPortList = @()
$ListServices = Get-Content -Path $listModuleFullFile

function Get-MD5-File {
    param (
        $Username,
        $Hostname,
        $ModulePath
    )

    $sshCommand = @"
    ssh ${Username}@${Hostname} "find `"${ModulePath}/usr/servers/defaultServer/dropins`" -type f \( -name "*.war" -o -name "*.jar" \) -execdir md5sum {} \;"
"@

    $outputString = (Invoke-Expression -Command $sshCommand | Out-String).TrimEnd([Environment]::NewLine)

    $result = @($outputString -split "`n" | ForEach-Object {
        ($_ -split "=" | Select-Object -First 1).Trim()
    })  

    return $result

}

function Step-Pre-Process {
    param (
        $Username,
        $Hostname,
        $ModulePath
    )
    $dict = @{}
    $keys = @()
    $values = @()

    $ContentFile = Get-MD5-File -Username $Username -Hostname $Hostname  -ModulePath $ModulePath
    foreach ($cFile in $ContentFile) {
        $cFileSplited = $cFile -split " "
        $keys += $cFileSplited[-1]
        $values += $cFileSplited[0]
    }

    for ($i = 0; $i -lt $keys.Count; $i++) {
        $dict[$keys[$i]] = $values[$i]
    }
    return $dict
}

function Step-Compare-File {
    param (
        $FileA,
        $FileB
    )

    $MD5WarFileHost1 = $FileA
    $MD5WarFileHost2 = $FileB

    $areEqual = $true
    if ($MD5WarFileHost1.Count -eq $MD5WarFileHost2.Count) {
        foreach ($key in $MD5WarFileHost1.Keys) {
            if ($MD5WarFileHost1[$key] -ne $MD5WarFileHost2[$key]) {
                $areEqual = $false
                break
            }
        }
    } else {
        $areEqual = $false
    }
    
    return $areEqual

}

function Step-Compare-War-File-Multiple-Servers {
    param (
        $Username,
        $ModulePath,
        $ListServers
    )
	$MD5WarFiles = @() 
    foreach ($server in $ListServers) {
        $MD5WarFile = Step-Pre-Process -Username $Username -Hostname $server -ModulePath $ModulePath
		$MD5WarFiles += $MD5WarFile
		Write-Host "War Flies on ${server}"
		Write-Output $MD5WarFile
    }
    $areEqual = $true
    for ($i = 0; $i -lt $MD5WarFiles.Count - 1; $i++) {
        $areEqual = Step-Compare-File -FileA $MD5WarFiles[$i] -FileB $MD5WarFiles[$i + 1]
        if (! $areEqual) {
            Write-Warning "Not Equal."
            break
        }
    }

    if ($areEqual) {
        Write-Host "Equal." -BackgroundColor Green 
    } else {
        Write-Warning "Not Equal."
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
    param {
        $List
    }

    foreach ($ServiceAndPort in $List) {
        if ($ServiceAndPort -match '\.\d+$') {
            $ServiceAndPort = $ServiceAndPort -split '\.'
            $Port = $ServiceAndPort[-1]
            $ValidatedPortList += $Port
        }
    }

    
}

Get-Validate-Port -List $ListServices
Get-Validate-Port -List $specialServices

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
                Step-Compare-War-File-Multiple-Servers -Username 'hydro' -ListServers $AllServers -ModulePath "${sourcePath}${ServiceAndPort}"
            }
        }
        $sourcePath = "/data"
        foreach ($ServiceAndPort in $specialServices) {
            if ($ServiceAndPort -match '\.\d+$') {
                Step-Compare-War-File-Multiple-Servers -Username 'hydro' -ListServers $AllServers -ModulePath "${sourcePath}${ServiceAndPort}"
            }
        }
    } else {
        $ServiceName = $(Get-Variable -Name $PortService -ValueOnly)
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
        Step-Compare-War-File-Multiple-Servers -Username 'hydro' -ListServers $AllServers -ModulePath "${sourcePath}/${moduleName}"     
    } 

} else {
    Write-Error "Please select a port from the list above to deploy your service."
}
