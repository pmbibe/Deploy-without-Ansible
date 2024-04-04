#!/bin/bash

set -e

exit_handler() {
    local exit_code="$?"
    if [ $exit_code -ne 0 ]; then
        echo "Error: Script encountered an error. For more details, please contact ducptm@tpb.com.vn" >&2
    fi
    exit $exit_code
}

trap exit_handler EXIT

dbs_ha_path='/Your/Path/'
platform_ha_path='/Your/Path/'
web_sphere_path='/tmp/'
web_sphere_zip='wlp24002.zip'
web_sphere_directory='wlp_24.0.0.2'

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a | --action)
            shift
            action="$1"
            ;;
        -st | --service-type)
            shift
            service_type="$1"
            ;;
        -sp | --service-port)
            shift
            port_of_service="$1"
            ;;
        -bv | --backup-verison)
            shift
            backup_version="$1"
            ;;            
        *)
            echo "Upgrade webSphere

usage: upgrade_web_sphere.sh -a Action -st ServiceType -sp ServicePort

Arguments:
   -a,  --action        Choose action: start, stop, backup, deploy or rollback
   -st, --service-type  Choose action: dbs or platform
   -sp, --service-port  Running port of service"

            exit 1
            ;;
    esac
    shift
done

stop_module() {

    local module_directory=$1

    pid=(`ps axu | grep $module_directory | grep -v grep | awk '{print $2}'`)
    if [ -n "$pid" ];then
        echo "Stopping module ..."
        kill -9 $pid
        echo "Module stopped"
    else
        echo "This module has not been run"
    fi
}

verify_version() {

    local module_path=$1
    local module_directory=$2
    echo "Verifying Websphere version"
    if [ -d ${module_path}/${module_directory} ]; then
        chmod +x ${module_path}/${module_directory}/bin/server 
        version=$(${module_path}/${module_directory}/bin/server version | awk 'END{print $4}')
        echo "Your Websphere version is $version"

    else
        echo "Not found $module_directory."
        exit 1
    fi    


}


start_module() {
    local module_path=$1
    local module_directory=$2
    echo "Starting module"
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
        unzip ${web_sphere_path}${web_sphere_zip} -d ${web_sphere_path}
        rsync -azrv --exclude=${web_sphere_path}${web_sphere_directory}/wlp/usr ${web_sphere_path}${web_sphere_directory}/wlp/* ${module_path}/${module_directory}

    else
        echo "Not found. Copy ${web_sphere_zip} to ${web_sphere_path} first"
        exit 1
    fi

    echo "Module has been deployed"

}

rollback_web_sphere(){
    local module_path=$1
    local module_directory=$2
    local backup_version=$3
    if [ -d ${module_path}/${module_directory}_${backup_version} ]; then

        stop_module $module_directory

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


case "$service_type" in
    "dbs")
        path=$dbs_ha_path
        ;;
    "platform")
        path=$platform_ha_path
        ;;
    *)
        echo "Choose action: dbs or platform"
        exit 1
        ;;
esac

module_name=$(find $path -maxdepth 1 -type d | grep -E "\.$port_of_service$")

if [[ $module_name ]]; then
    echo "********** Found MODULE: $module_name FROM PORT $port_of_service **********"
else
    echo "Module not found"
    exit 1
fi

IFS='/' read -r -a module_name_arr <<< "$module_name"

case "$action" in
    "stop")
        echo "Stop module ${module_name_arr[-1]}"
        stop_module $module_name
        ;;
    "start")
        echo "Start module ${module_name_arr[-1]}"
        start_module $module_name
        ;;
    "backup")
        echo "Backup module ${module_name_arr[-1]}"
        backup_module $path $module_name
        ;;
    "deploy")
        echo "Deploy module ${module_name_arr[-1]}"
        deploy_web_sphere $path $module_name $web_sphere_path $web_sphere_zip $web_sphere_directory
        ;;
    "rollback")
        echo "Rollback module ${module_name_arr[-1]}"
        rollback_web_sphere $path $module_name $backup_version
        ;;
    *)
        echo "Choose action: start, stop, backup, deploy or rollback"
        exit 1
        ;;
esac
