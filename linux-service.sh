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

path=''

phase=$1
port_of_service=$2

# module_name=$(find $path -maxdepth 1 -type d | grep -E "\.$port_of_service$")

echo "********** Found MODULE: $module_name FROM PORT $port_of_service **********"

module_name="tpb"

dir_all_needed_files_deployed="/home/quantri/ducptm/${module_name}_deploy_today"

# Server.env/Server_off.env file
file_server_off_env_update="/home/quantri/ducptm/server_off_vars.txt"
file_server_off_env_backup="/home/quantri/ducptm/server_off.env_$(date +'%Y%m%d')"
file_server_off_env="/home/quantri/ducptm/server_off.env"

# War directory
dir_war_backup="/home/quantri/ducptm/dropins_$(date +'%Y%m%d')"
dir_war="/home/quantri/ducptm/dropins"

#jvm.options file
file_jvm_options_backup="/home/quantri/ducptm/jvm.options_$(date +'%Y%m%d')"
file_jvm_options="/home/quantri/ducptm/jvm.options"

stop_module() {
    pid=(`ps axu | grep $module_name | grep -v grep | awk {print $2}`)
    if [ -n "$pid" ];then
        echo "Stopping module ..."
        kill -9 $pid
        echo "Module stopped"
    else
        echo "This module has not been run"
    fi
}

back_up_war() {
    if [ ! -d $dir_war_backup ]; then
        mkdir -p $dir_war_backup
        find "$dir_war" -type f -name "*.war" -execdir cp {} "$dir_war_backup/{}_$(date +'%Y%m%d')" \;
    else
        echo "War files have been backed up. Ignore this step"
    fi

}
back_up_jvm() {
    if [ ! -f $file_jvm_options_backup ]; then
        cp $file_jvm_options $file_jvm_options_backup
    else
        echo "JVM Options file has been backed up. Ignore this step"
    fi
}
back_up_server_off_env() {
    if [ ! -f $file_server_off_env_backup ]; then
        cp $file_server_off_env $file_server_off_env_backup
    else
        echo "Server/Server_off env file has been backed up. Ignore this step"
    fi

}

pre_process(){
    local line=$line
    trimmed_line="${line#"${line%%[![:space:]]*}"}"
    trimmed_line="${trimmed_line%"${trimmed_line##*[![:space:]]}"}"
    echo $trimmed_line
}

get_details_server_off_env() {
    declare -a list_action
    declare -A dict_action
    is_the_first=false

    if [ -f "$file_server_off_env_update" ]; then
        # Read the file line by line
        while IFS= read -r line; do
            processed_line=$(pre_process $line)
            if [[ $processed_line =~ --\ ([[:alnum:]]+) && $is_the_first ]]; then
                action="${processed_line:3}"
                if [[ ! " ${list_action[@]} " =~ " $action " ]]; then
                    list_action+=("$action")
                    current_action="$action"
                fi
                is_the_first=true
            # Check if the line is "--" and it's the first variable
            elif [[ $processed_line = "--" && $is_the_first ]]; then
                is_the_first=false
            # Check if it's the first variable
            elif $is_the_first; then
                dict_action["$current_action"]+="$processed_line,"
            fi
        done < $file_server_off_env_update

        for key in "${!dict_action[@]}"; do
            # Split the concatenated string back into an array
            IFS=, read -ra value_arr <<< "${dict_action[$key]}"
            eval "$key=\"${value_arr[@]}\""
        done

    else
        echo "Nothing to update Server/Server_off Env files"
    fi


}

insert_server_off_env_vars() {
    for i_var in $Insert; do
        sed -i "\$a$i_var" $file_server_off_env
    done

}

update_server_off_env_vars() {
    local time_execute=$time_execute
    for i_var in $Update; do
        IFS='=' read -r variable_name variable_value <<< "$i_var"
        sed -i "/^$variable_name/ s/$/ #---- Updated, for more details check at $time_execute/" $file_server_off_env
        sed -i "/^$variable_name/ s/^/#/" $file_server_off_env
        sed -i "\$a$i_var" $file_server_off_env
    done

}

deploy_server_off_env() {
    time_execute=$(date +'%Y%m%d%H%M%S')
    sed -i "\$a#$time_execute Insert/Update variables" $file_server_off_env
    get_details_server_off_env
    update_server_off_env_vars
    insert_server_off_env_vars
}

deploy_wars_files() {
    if [ ! -d $dir_all_needed_files_deployed/dropins ]; then
        echo "Please run PRE-DEPLOY first" >&2
        exit 1
    else
        war_files=$(find "$dir_all_needed_files_deployed/dropins" -type f -name "*.war")
        # Check if the variable war_files is empty
        if [ -n "$war_files" ]; then
            find "$dir_all_needed_files_deployed/dropins" -type f -name "*.war" -execdir cp {} "$dir_war/{}" \;
        else
            # Print an error message if no .war files are found
            echo "Error: No .war files found in $dir_all_needed_files_deployed/dropins" >&2
            exit 1
        fi
        
    fi
}

deploy_jvm_options_file() {
    if [ ! -d $dir_all_needed_files_deployed ]; then
        echo "Please run PRE-DEPLOY first" >&2
        exit 1
    fi
    if [ ! -f $dir_all_needed_files_deployed/jvm.options ]; then
        echo "Error: No jvm.options file found in $dir_all_needed_files_deployed" >&2
        exit 1
    else
        cp $dir_all_needed_files_deployed/jvm.options $file_jvm_options
    fi
}

back_up() {
   echo "---------- Back up War files ----------"
   back_up_war
   echo "Back up War files done"
   echo "---------- Back up JVM Options files ----------"
   back_up_jvm
   echo "Back up JVM Options files done"
   echo "---------- Back up Server/Server_off env files ----------"
   back_up_server_off_env
   echo "Back up Server/Server_off env files done"
}

deploy() {
    echo "---------- Deploying War files ----------"
    deploy_wars_files
    echo "Deploy War files DONE"
    echo "---------- Deploying Server/Server_off env files ----------"
    deploy_server_off_env
    echo "Deploy Server/Server_off env files DONE"
    echo "---------- Deploying jvm.options files ----------"
    deploy_jvm_options_file
    echo "Deploy jvm.options files DONE"

}

pre_deploy() {
    if [ ! -d $dir_all_needed_files_deployed ]; then
        mkdir -p $dir_all_needed_files_deployed
        if [ ! -d $dir_all_needed_files_deployed/dropins ]; then
            mkdir -p $dir_all_needed_files_deployed/dropins
        fi
    fi
}

case "$phase" in
    "pre_deploy")
        echo "---------- Pre-Deploying ----------"
        pre_deploy
        echo "Pre-Deploy DONE"
        ;;
    "back_up")
        echo "---------- Backing up ----------"
        back_up
        echo "Back up DONE"
        ;;
    "deploy")
        echo "---------- Deploying ----------"
        deploy
        echo "Congratulations. Your deployment has been SUCCESS"
        ;;
    *)
        echo "Choose phase: pre_deploy, back_up or deploy"
        ;;
esac
