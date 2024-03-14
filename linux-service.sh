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

path='/data/hydro-liberty/dbs_ha/'

# module_name=$(find $path -maxdepth 1 -type d | grep -E "\.$1$")

# Server.env/Server_off.env file
server_off_env_file_update="/home/quantri/ducptm/server_off_vars.txt"
server_off_env_file_backup="/home/quantri/ducptm/server_off.env_$(date +'%Y%m%d')"
server_off_env_file="/home/quantri/ducptm/server_off.env"

# War directory
dir_war_backup="/home/quantri/ducptm/dropins_$(date +'%Y%m%d')"
dir_war="/home/quantri/ducptm/dropins"

#jvm.options file
jvm_options_file_backup="/home/quantri/ducptm/jvm.options_$(date +'%Y%m%d')"
jvm_options_file="/home/quantri/ducptm/jvm.options"


# # Server.env/Server_off.env file
# server_off_env_file_update="$path$module_name/usr/servers/defaultServer/server_off_vars.txt"
# server_off_env_file_backup="$path$module_name/usr/servers/defaultServer/server_off.env_$(date +'%Y%m%d')"
# server_off_env_file="$path$module_name/usr/servers/defaultServer/server_off.env"

# # War directory
# dir_war_backup="$path$module_name/usr/servers/defaultServer/dropins_$(date +'%Y%m%d')"
# dir_war="$path$module_name/usr/servers/defaultServer/dropins"

# #jvm.options file
# jvm_options_file_backup="$path$module_name/usr/servers/defaultServer/jvm.options_$(date +'%Y%m%d')"
# jvm_options_file="$path$module_name/usr/servers/defaultServer/jvm.options"



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
    if [ ! -f $jvm_options_file_backup ]; then
        cp $jvm_options_file $jvm_options_file_backup
    else
        echo "JVM Options file has been backed up. Ignore this step"
    fi
}
back_up_server_off_env() {
    if [ ! -f $server_off_env_file_backup ]; then
        cp $server_off_env_file $server_off_env_file_backup
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

    if [ -f "$server_off_env_file_update" ]; then
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
        done < $server_off_env_file_update

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
        sed -i "\$a$i_var" $server_off_env_file
    done

}

update_server_off_env_vars() {
    local time_execute=$time_execute
    for i_var in $Update; do
        IFS='=' read -r variable_name variable_value <<< "$i_var"
        sed -i "/^$variable_name/ s/$/ #---- Updated, for more details check at $time_execute/" $server_off_env_file
        sed -i "/^$variable_name/ s/^/#/" $server_off_env_file
        sed -i "\$a$i_var" $server_off_env_file
    done

}

deploy_server_off_env() {
    time_execute=$(date +'%Y%m%d%H%M%S')
    sed -i "\$a#$time_execute Insert/Update variables" $server_off_env_file
    get_details_server_off_env
    update_server_off_env_vars
    insert_server_off_env_vars
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
    deploy_server_off_env    
}


back_up
echo "---------- Deploying ----------"
deploy
echo "Congratulations. Your deployment has been SUCCESS"
