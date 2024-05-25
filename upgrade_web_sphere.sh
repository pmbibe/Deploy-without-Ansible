#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

web_sphere_path='/tmp/'
web_sphere_zip='wlp_24002.zip'
web_sphere_directory='wlp_24.0.0.2'

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a | --action)
            shift
            action="$1"
            ;;
        -s | --service)
            shift
            service_d="$1"
            ;;            
        -bv | --backup-verison)
            shift
            backup_version="$1"
            ;;

        *)
            echo "Upgrade webSphere

usage: upgrade_web_sphere.sh -a Action

Arguments:
   -a,  --action        Choose action: all, start, stop, backup, deploy or rollback
   all: Run stop, backup, deploy and start service"

            exit 1
            ;;
    esac
    shift
done


bi_service=('')

be=('')

exceptional_service=('')

pm_service=('')

get_service_path() {
    local service=$1
    if [[ " ${bi_service[*]} " =~ " $service " ]]; then
        echo "/data/ducptm/bi"
    elif [[ " ${be[*]} " =~ " $service " ]]; then
        echo "/data/ducptm/be"
    elif [[ " ${exceptional_service[*]} " =~ " $service " ]]; then
        echo "/data/ducptm"    
    elif [[ " ${pm_service[*]} " =~ " $service " ]]; then
        echo "/data/ducptm/pm"           
    fi
}

stop_module() {

    local module_directory=$1

    pid=(`ps axu | grep $module_directory | grep -v grep | awk '{print $2}'`)
    if [ -n "$pid" ];then
        echo "Stopping module $module_directory ..."
        kill -9 $pid
        echo $pid
        echo "Module $module_directory stopped"
    else
        echo "This module has not been run"
    fi
}

verify_version() {

    local module_path=$1
    local module_directory=$2
    echo "Verifying Websphere version $module_directory"
    if [ -d ${module_path}/${module_directory} ]; then
        chmod +x ${module_path}/${module_directory}/bin/server 
        version=$(${module_path}/${module_directory}/bin/server version | awk 'END{print $4}')
        echo "Your Websphere version $module_directory is $version"

    else
        echo "Not found $module_directory."
        exit 1
    fi    


}

start_module() {
    local module_path=$1
    local module_directory=$2
    echo "Starting module $module_directory"
    if [ -d ${module_path}/${module_directory} ]; then
        chmod +x ${module_path}/${module_directory}/bin/server && ${module_path}/${module_directory}/bin/server start
    else
        echo "Not found $module_directory."
        exit 1
    fi    

}

backup_module() {

    local module_path=$1
    local module_directory=$2
    
    echo "Backing up module $module_directory"
    if [ -d ${module_path}/${module_directory} ]; then
        cp -r ${module_path}/${module_directory} ${module_path}/${module_directory}_$(date +'%Y%m%d')
        echo "Done. Backup directory: ${module_path}/${module_directory}_$(date +'%Y%m%d')"
    else
        echo "Not found $module_directory."
        exit 1
    fi
}

deploy_web_sphere(){
    local module_path=$1
    local module_directory=$2
    local web_sphere_path=$3
    local web_sphere_zip=$4
    local web_sphere_directory=$5
    
    echo "Deploying module $module_directory"

    if [ -f ${web_sphere_path}${web_sphere_zip} ]; then
        # unzip ${web_sphere_path}${web_sphere_zip} -d ${web_sphere_path}
        rsync -azr --exclude=usr ${web_sphere_path}${web_sphere_directory}/wlp/* ${module_path}/${module_directory}

    else
        echo "Not found. Copy ${web_sphere_zip} to ${web_sphere_path} first"
        exit 1
    fi

    echo "Module $module_directory has been deployed"

}


rollback_web_sphere(){
    local module_path=$1
    local module_directory=$2
    local backup_version=$3
    if [ -d ${module_path}/${module_directory}_${backup_version} ]; then

        # stop_module $module_directory

        echo "Rollback from ${backup_version} to current version"

        rm -rf ${module_path}/${module_directory}

        mv ${module_path}/${module_directory}_${backup_version} ${module_path}/${module_directory}

        echo "Rollback done"

        # start_module $module_name

    else
        echo "Not found Backup version ${backup_version}"
        exit 1
    fi
}


case "$action" in
    "all")
	    unzip ${web_sphere_path}${web_sphere_zip} -d ${web_sphere_path}
        for service in "${bi_service[@]}"; do
            service_path=$(get_service_path $service)
            stop_module $service
            backup_module $service_path $service
            deploy_web_sphere $service_path $service $web_sphere_path $web_sphere_zip $web_sphere_directory            
            verify_version $service_path $service
			start_module $service_path $service
        done
        for service in "${be[@]}"; do
            service_path=$(get_service_path $service)
            # stop_module $service
            backup_module $service_path $service
            deploy_web_sphere $service_path $service $web_sphere_path $web_sphere_zip $web_sphere_directory                
            verify_version $service_path $service
        done
        for service in "${exceptional_service[@]}"; do
            service_path=$(get_service_path $service)
            stop_module $service
            backup_module $service_path $service
            deploy_web_sphere $service_path $service $web_sphere_path $web_sphere_zip $web_sphere_directory                
            verify_version $service_path $service
			start_module $service_path $service
        done
        for service in "${pm_service[@]}"; do
            service_path=$(get_service_path $service)
            stop_module $service
            backup_module $service_path "pm.wlp-17.0.0.4"
            deploy_web_sphere $service_path "pm.wlp-17.0.0.4" $web_sphere_path $web_sphere_zip $web_sphere_directory                
            verify_version $service_path "pm.wlp-17.0.0.4"
			${service_path}/pm.wlp-17.0.0.4/bin/server start $service
        done                        
        ;;
    "verify")
        verify_version $service_path $service
        ;;
    "rollback")
        rollback_web_sphere $service_path $service $backup_version
        verify_version $service_path $service
        ;;
    *)
        echo "Choose action: all, verify or rollback"
        exit 1
        ;;
esac




