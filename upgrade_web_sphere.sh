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

pmbibe_path='/data/pmbibe-ducptm/pmbibe/'
ducptm_path='/data/pmbibe-ducptm/ducptm/'
web_sphere_path='/tmp/'
web_sphere_zip='wlp24002.zip'

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
        *)
            echo "Upgrade webSphere

usage: upgrade_web_sphere.sh -a Action -st ServiceType -sp ServicePort

Arguments:
   -a,  --action        Choose action: start, stop, backup, deploy or rollback
   -st, --service-type  Choose action: ducptm or ducptm
   -sp, --service-port  Running port of service"

            exit 1
            ;;
    esac
    shift
done

stop_module() {
    local module_name=$1

    pids=(`ps axu | grep $module_name | grep -v grep | awk '{print $2}'`)
    if [ -n "$pid" ];then
        for pid in ${pids[@]}; do
            echo "Stopping module with PID: ${pid} ..."
            kill -9 $pid
        done
        echo "Module stopped"
    else
        echo "This module has not been run"
    fi
}
start_module() {
    local module_name=$1

    ${module_name}/bin/server start

}

backup_web_sphere(){
    local module_name=$1

    cp -r ${module_name} ${module_name}_$(date +'%Y%m%d')

}

deploy_web_sphere(){
    local module_name=$1
    
    if [ -f ${web_sphere_path}${web_sphere_zip} ]; then

        IFS='.' read -r -a web_sphere <<< "$web_sphere_zip"

        upzip ${web_sphere_path}${web_sphere_zip} -d ${web_sphere_path}

        cp -r ${web_sphere_path}${web_sphere[1]}/wlp/* $module_name

    else
        echo "Not found. Copy ${web_sphere_zip} to ${web_sphere_path} first"
        exit 1
    fi

}

rollback_web_sphere(){
    local module_name=$1

    rm -rf ${module_name}
    mv ${module_name}_$(date +'%Y%m%d') ${module_name}
}


case "$service_type" in
    "pmbibe")
        path=$pmbibe_path
        ;;
    "ducptm")
        path=$ducptm_path
        ;;
    *)
        echo "Choose action: ducptm or pmbibe"
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
        backup_web_sphere $module_name
        ;;
    "deploy")
        echo "Deploy module ${module_name_arr[-1]}"
        deploy_web_sphere $module_name
        ;;
    "rollback")
        echo "Rollback module ${module_name_arr[-1]}"
        rollback_web_sphere $module_name
        ;;
    *)
        echo "Choose action: start, stop, backup, deploy or rollback"
        exit 1
        ;;
esac
