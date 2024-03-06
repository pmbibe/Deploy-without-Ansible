#  .\UpgradeActiveMQ.ps1 -Platform VM -Site DC -DryrunMode y
#  To deploy: set -DryrunMode N. Default Y: Dry-run mode
#  Set Platform variable VM/K8S 
#  Set Site variable DC/DR/DC2

param(
    [Parameter(mandatory=$true)][ValidateSet('K8S','VM')][string]$Platform,
    [Parameter(mandatory=$true)][ValidateSet('DC','DR','DC2')][string]$Site,
    [Parameter(Mandatory=$false)][string[]]$DRServer= @(''),
    [Parameter(Mandatory=$false)][string[]]$DCServer= @(''),
    [Parameter()][ValidateSet('Y','N')][string]$DryrunMode = 'Y',
    [Parameter()][string]$DCUser = '',
    [Parameter()][string]$DCPass = "",
    [Parameter()][string]$DRUser = '',
    [Parameter()][string]$DRPass = "",
    # ----- DRBastion Information -----
    [Parameter()][string]$DRBastionHost = '',
    [Parameter()][string]$DRBastionUser = '',
    [Parameter()][string]$DRBastionPass = "",
    [Parameter()][string]$DRregistryURL = '',
    # ----- DRBastion Information -----
    [Parameter()][string]$DCBastionHost = '',
    [Parameter()][string]$DCBastionUser = '',
    [Parameter()][string]$DCBastionPass = "",
    [Parameter()][string]$DCregistryURL = '',
    # ----- DRBastion Information -----
    [Parameter()][string]$DC2BastionHost = '',
    [Parameter()][string]$DC2BastionUser = '',
    [Parameter()][string]$DC2BastionPass = '',
    [Parameter()][string]$DC2registryURL = ''
)

function CheckIsDryrunMode {
    param (
        $Command
    )
    if ($DryrunMode -eq 'Y') {
        Write-Host $Command
    } elseif ($DryrunMode -eq 'N') {
        Invoke-Expression $Command  
    }
}
function RetryInputUser {
    $retryCount = 3
    for ($i = 1; $i -le $retryCount; $i++) {
        $userInput =  Read-Host "Continuing deploy (Y/N)?"
    
        if ($userInput -eq 'Y' -or $userInput -eq 'N') {
            return $userInput
        } else {
            Write-Host "Invalid input. Please enter Y or N."
            
        }
    }

    break
}

function CopyFromLocalToServer {
    param (
        $Username,
        $Hostname,
        $Password,
        $SourcePath,
        $DestinationPath

    )

    $DestinationUri = "${Username}@${Hostname}:${DestinationPath}"

    if (Test-Path -Path $SourcePath) {
        # Get information about the item
        $item = Get-Item -Path $SourcePath
    
        # Check if it's a file
        if ($item.PSIsContainer) {
            $scpCommand = "scp -r ${SourcePath} ${DestinationUri}"
        } else {
            $scpCommand = "scp ${SourcePath} ${DestinationUri}"
        }
    } else {
        Write-Host "$SourcePath does not exist."
    }

    Write-Host "Copy and Paste password ${Password}" -ForegroundColor Cyan

    CheckIsDryrunMode -Command $scpCommand

    # Invoke-Expression -Command $scpCommand

}

function UpgradeActiveMQVM {
    param (
        $Username,
        $Hostname,
        $Password
    )
    Write-Host "---------- Deploying to ${Hostname} ----------" -ForegroundColor Yellow
    $ChecklistPath = ''

    Write-Host "---------- Copying apache-activemq-6.0.0 ----------" -ForegroundColor Yellow
    $SourceFolderActiveMQ = "${ChecklistPath}\VM\apache-activemq-6.0.0"
    $DestinationActiveMQ = ''
    CopyFromLocalToServer -Username $User -Hostname $server -Password $Pass -SourcePath $SourceFolderActiveMQ -DestinationPath $DestinationActiveMQ

    Write-Host "---------- Copying jdk-17.0.9 ----------" -ForegroundColor Yellow
    $SourceFolderJDK = "${ChecklistPath}\jdk17\jdk-17_linux-x64_bin.tar.gz"
    $DestinationJDK = ''
    CopyFromLocalToServer -Username $User -Hostname $server -Password $Pass -SourcePath $SourceFolderJDK -DestinationPath $DestinationJDK

    Write-Host "---------- Config ActiveMQ ----------" -ForegroundColor Yellow

    $newOpts = '    ACTIVEMQ_OPTS=`"`"`$ACTIVEMQ_OPTS_MEMORY -Djava.util.logging.config.file=logging.properties -Djava.security.auth.login.config=`$ACTIVEMQ_CONF\/login.config -Dorg.apache.activemq.SERIALIZABLE_PACKAGES=*`"`"'
    $oldOpts = 'ACTIVEMQ_OPTS=`".`$ACTIVEMQ_OPTS_MEMORY -javaagent:jmx_prometheus_javaagent-0.13.0.jar=8081:config.yml -Djava.util.logging.config.file=logging.properties -Djava.security.auth.login.config=`$ACTIVEMQ_CONF\/login.config -Dorg.apache.activemq.SERIALIZABLE_PACKAGES=.*`"'

    $sshCommand = @"
ssh ${Username}@${Hostname} "cd /data && \
tar -xvf /data/jdk-17_linux-x64_bin.tar.gz && \
chmod +x /data/hydro-liberty/apache-activemq-6.0.0/bin/activemq && \
echo 'Replace JAVA_HOME in /data/hydro-liberty/apache-activemq-6.0.0/bin/setenv' && \
sed -i 's|/usr/lib/jvm/jdk-17.0.9|/data/jdk-17.0.9|' /data/hydro-liberty/apache-activemq-6.0.0/bin/setenv && \
sed -i '/$oldOpts/ s/^/#/' /data/hydro-liberty/apache-activemq-6.0.0/bin/setenv && \
echo 'Replace ACTIVEMQ_OPTS in /data/hydro-liberty/apache-activemq-6.0.0/bin/setenv' && \
sed -i '/$oldOpts/ a\$newOpts' /data/hydro-liberty/apache-activemq-6.0.0/bin/setenv"
"@

    CheckIsDryrunMode -Command $sshCommand

    Write-Host "---------- Start ActiveMQ ----------" -ForegroundColor Yellow

    $deployCommand = @"
echo 'Start activeMQ' && \
cd /data/hydro-liberty/apache-activemq-6.0.0/ && \
./bin/activemq start
"@
    if ($DryrunMode -eq 'N') {
        $userInput = RetryInputUser
    } else {
        $userInput = 'Y'
    }

    if ($userInput -eq 'Y' -or $userInput -eq 'y') {
        Write-Host "Auto deploying ..... " -ForegroundColor Cyan
        CheckIsDryrunMode -Command $deployCommand
    } elseif ($userInput -eq 'N' -or $userInput -eq 'n') {
        Write-Host "Copy and paste these commands to ${Hostname} for deploying manual ..... " -ForegroundColor Cyan
        CheckIsDryrunMode -Command $deployCommand
    } else {
        Write-Warning "Invalid input. Please enter Y or N."
    }
    # Invoke-Expression -Command $sshCommand
    Write-Host "---------- Deployed to ${Hostname} ----------" -ForegroundColor Yellow
}

function UpgradeActiveMQK8S {
    param (
        $Username,
        $Hostname,
        $Password,
        $registryURL
    )

    $ChecklistPath = ''

    Write-Host "---------- Copying Image apache-activemq-6.0.0 ----------" -ForegroundColor Yellow
    $imageName = "apache-activemq-6.0.0.tar"
    $SourceFolderImage = "${ChecklistPath}\Xplat-K8S\image\${imageName}"
    $DestinationImage = "/home/${Username}"
    $imageTag = "apache-activemq:6.0.0"
    CopyFromLocalToServer -Username $Username -Hostname $Hostname -Password $Password -SourcePath $SourceFolderImage -DestinationPath $DestinationImage
    $projectName = ''

    $sshCommand = @"
ssh ${Username}@${Hostname} "podmanLoadOutput=```$(podman load -i ${imageName}) && \
loadedImageLine=```$(echo ```"```$podmanLoadOutput``" | tail -n 1) && \
imageNameTag=```$(echo ``"```$loadedImageLine``" | awk '{print ```$NF}') && \
podman tag ```$imageNameTag ${registryURL}/${projectName}/${imageTag} && \
podman push ${registryURL}/${projectName}/${imageTag}"
"@
    CheckIsDryrunMode -Command $sshCommand

#   Helm Upgrade
    Write-Host "---------- Update Helm file ----------" -ForegroundColor Yellow
    $HelmPath = ''
    $ServiceName = 'apache-activemq'
    $sshCommand = @"
ssh ${Username}@${Hostname} "sed -i '/  tag:/ s/^/#/' ${HelmPath}/${ServiceName}/test_values.yaml && \
echo 'Update tag in values file' && \
sed -i '/  tag:/ a\  tag: ``"```"6.0.0``"```"' ${HelmPath}/${ServiceName}/test_values.yaml && \
echo 'Update deployment' && \
sed -i 's|              mountPath: /home/alpine/activemq-5.15.8|              mountPath: /home/apache-activemq-6.0.0|' ${HelmPath}/${ServiceName}/test_deployment.yaml"
"@

    CheckIsDryrunMode -Command $sshCommand

    Write-Host "---------- Run Helm upgrade in Dry-run and Debug Mode ----------" -ForegroundColor Yellow
    $sshCommand = @"
ssh ${Username}@${Hostname} "cd ${HelmPath}/${ServiceName} &&  \
helm upgrade apache-activemq --dry-run --debug . -f values.yaml -n ${projectName}"
"@

    CheckIsDryrunMode -Command $sshCommand

    Write-Host "---------- Run Helm upgrade ----------" -ForegroundColor Yellow

    $deployCommand = @"
cd ${HelmPath}/${ServiceName} &&  \
helm upgrade apache-activemq . -f values.yaml -n ${projectName}
"@
    $sshCommand = @"
ssh ${Username}@${Hostname} "${deployCommand}"
"@

    if ($DryrunMode -eq 'N') {
        $userInput = RetryInputUser
    } else {
        $userInput = 'Y'
    }
        if ($userInput -eq 'Y' -or $userInput -eq 'N') {
            if ($userInput -eq 'Y' -or $userInput -eq 'y') {
                Write-Host "Auto deploying ..... " -ForegroundColor Cyan
                CheckIsDryrunMode -Command $deployCommand
            } elseif ($userInput -eq 'N' -or $userInput -eq 'n') {
                Write-Host "Copy and paste these commands to ${Hostname} for deploying manual ..... " -ForegroundColor Cyan
                CheckIsDryrunMode -Command $deployCommand
            }
        } else {
            Write-Host "Invalid input. Please enter Y or N."
            break
        }

    
}

try {
    if ($DryrunMode -eq 'N') {
        $userInput = $(Write-Host "Ensure you turn off Edge and Forwarder service before updating. Please enter 'I did' for continuing: " -ForegroundColor Cyan -NoNewLine; Read-Host)
        if ($userInput -eq 'I did') {
            Write-Host "Auto deploying ..... " -ForegroundColor Cyan
        } else {
            Write-Warning "Invalid input. Please enter I did"
        }    
    }

        switch ($Platform) {
            "K8S" {
                if ($Site -eq "DC") {
                    $BastionHost = $DCBastionHost
                    $BastionUser = $DCBastionUser
                    $BastionPass = $DCBastionPass
                    $registryURL = $DCregistryURLs
                } elseif ($Site -eq "DR") {
                    $BastionHost = $DRBastionHost
                    $BastionUser = $DRBastionUser
                    $BastionPass = $DRBastionPass
                    $registryURL = $DRregistryURL                    
                } elseif ($Site -eq "DC2") {
                    $BastionHost = $DC2BastionHost
                    $BastionUser = $DC2BastionUser
                    $BastionPass = $DC2BastionPass                    
                    $registryURL = $DC2registryURL
                }
                Write-Host "Deploy to K8S" -ForegroundColor Yellow
                UpgradeActiveMQK8S -Username $BastionUser -Hostname $BastionHost -Password $BastionPass -registryURL $registryURL
                Write-Host "Deployed to K8S" -ForegroundColor Yellow
            }
            "VM" {
                if ($Site -eq "DC") {
                    $ServersList = $DCServer
                    $User = $DCUser
                    $Pass = $DCPass
                } elseif ($Site -eq "DR") {
                    $ServersList = $DRServer
                    $User = $DRCUser
                    $Pass = $DRPass
                } else {
                    Write-Warning "With VM platform, choose DC or DR"
                }
                foreach ($server in $ServersList) {
                    Write-Host "Deploy to VM" -ForegroundColor Yellow
                    UpgradeActiveMQVM -Username $User -Hostname $server -Password $Pass
                    Write-Host "Deployed to VM" -ForegroundColor Yellow
                }   
            }                      
        
        }
     
} catch {

}

    
