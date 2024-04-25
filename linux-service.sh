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

path='/Your/Path/'

phase=$1
folder_deploy_today=$2

IFS='_' read -r -a folder_deploy_today_array <<< "$folder_deploy_today"
port_of_service=${folder_deploy_today_array[0]}

module_name=$(find $path -maxdepth 1 -type d | grep -E "\.$port_of_service$")

IFS='/' read -r -a module_name_array <<< "$module_name"

module_name=${module_name_array[-1]}

echo "********** Found MODULE: $module_name FROM PORT $port_of_service **********"

dir_all_needed_files_deployed="/Your/Home/Path/$folder_deploy_today"

# Server.env/Server_off.env file
file_server_off_env_update="$dir_all_needed_files_deployed/server_off_vars.txt"
file_server_off_env_backup="$path$module_name/usr/servers/defaultServer/server.env_$(date +'%Y%m%d')"
file_server_off_env="$path$module_name/usr/servers/defaultServer/server.env"

# War directory
dir_war_deploy="$dir_all_needed_files_deployed/dropins"
dir_war_backup="$path$module_name/usr/servers/defaultServer/dropins_$(date +'%Y%m%d')"
dir_war="$path$module_name/usr/servers/defaultServer/dropins"

#jvm.options file
file_jvm_options_backup="$path$module_name/usr/servers/defaultServer/jvm.options_$(date +'%Y%m%d')"
file_jvm_options="$path$module_name/usr/servers/defaultServer/jvm.options"



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
        find "$dir_war" -type f \( -name "*.war" -o -name "*.jar" \) -exec sh -c 'echo "$(date +%Y/%m/%d\ %H:%M:%S) Found $(basename $1)"; cp "$1" "$2/$(basename "$1")_$(date +%Y%m%d)"' sh {} "$dir_war_backup" \;
    else
        echo "$(date +'%Y/%m/%d %H:%M:%S') War files have been backed up. Ignore this step"
    fi

}
back_up_jvm() {
    if [ ! -f $file_jvm_options_backup ]; then
        cp $file_jvm_options $file_jvm_options_backup
    else
        echo "$(date +'%Y/%m/%d %H:%M:%S') JVM Options file has been backed up. Ignore this step"
    fi
}
back_up_server_off_env() {
    if [ ! -f $file_server_off_env_backup ]; then
        cp $file_server_off_env $file_server_off_env_backup
    else
        echo "$(date +'%Y/%m/%d %H:%M:%S') Server/Server_off env file has been backed up. Ignore this step"
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
        echo "$(date +'%Y/%m/%d %H:%M:%S') Nothing to update Server/Server_off Env files"
    fi


}


check_is_deploy_server_off_env() {
    action=$1
    for i_var in ${!action}; do
        if grep -q -E "^$i_var$" "$file_server_off_env"; then
            # Replace the value of Insert variable based on the action variable
            eval "$action=\${$action[@]/$i_var}"                   
        fi
    done 

}

insert_server_off_env_vars() {
    check_is_deploy_server_off_env 'Insert'
    for i_var in $Insert; do
        sed -i "\$a$i_var" $file_server_off_env
    done

}

update_server_off_env_vars() {
    local BPM=$BPM
    check_is_deploy_server_off_env 'Update'
    for i_var in $Update; do
        IFS='=' read -r variable_name variable_value <<< "$i_var"
        sed -i "/^$variable_name/ s/$/ #---- Updated, for more details check at $BPM/" $file_server_off_env
        sed -i "/^$variable_name/ s/^/#/" $file_server_off_env
        sed -i "\$a$i_var" $file_server_off_env
    done

}
deploy_server_off_env() {
    IFS='_' read -r -a folder_deploy_today_array <<< "$folder_deploy_today"
    BPM=${folder_deploy_today_array[-1]}
    sed -i "\$a#$BPM Insert/Update variables" $file_server_off_env
    get_details_server_off_env
    update_server_off_env_vars
    insert_server_off_env_vars
}

deploy_wars_files() {
    if [ ! -d $dir_war_deploy ]; then
        echo "$(date +'%Y/%m/%d %H:%M:%S') Please run PRE-DEPLOY first" >&2
        exit 1
    else
        war_files=$(find "$dir_war_deploy" -type f \( -name "*.war" -o -name "*.jar" \))
        # Check if the variable war_files is not empty
        if [ -n "$war_files" ]; then
            echo "$(date +'%Y/%m/%d %H:%M:%S') Copying files to $dir_war ..."
            
            cp -t "$dir_war" $war_files
        else
            # Print an error message if no .war files are found
            echo "$(date +'%Y/%m/%d %H:%M:%S') No .war/.jar files found in $dir_war_deploy" >&2
        fi
        
    fi
}

deploy_jvm_options_file() {
    if [ ! -d $dir_all_needed_files_deployed ]; then
        echo "$(date +'%Y/%m/%d %H:%M:%S') Please run PRE-DEPLOY first" >&2
        exit 1
    fi
    if [ ! -f $dir_all_needed_files_deployed/jvm.options ]; then
        echo "$(date +'%Y/%m/%d %H:%M:%S') No jvm.options file found in $dir_all_needed_files_deployed" >&2
    else
        cp $dir_all_needed_files_deployed/jvm.options $file_jvm_options
    fi
}

back_up() {
   echo "$(date +'%Y/%m/%d %H:%M:%S') ---------- Back up War files ----------"
   back_up_war
   echo "$(date +'%Y/%m/%d %H:%M:%S') Back up War files done"
   echo "$(date +'%Y/%m/%d %H:%M:%S') ---------- Back up JVM Options files ----------"
   back_up_jvm
   echo "$(date +'%Y/%m/%d %H:%M:%S') Back up JVM Options files done"
   echo "$(date +'%Y/%m/%d %H:%M:%S') ---------- Back up Server/Server_off env files ----------"
   back_up_server_off_env
   echo "$(date +'%Y/%m/%d %H:%M:%S') Back up Server/Server_off env files done"
}

deploy() {
    echo "$(date +'%Y/%m/%d %H:%M:%S') ---------- Deploying War files ----------"
    deploy_wars_files
    echo "$(date +'%Y/%m/%d %H:%M:%S') Deploy War files DONE"
    echo "$(date +'%Y/%m/%d %H:%M:%S') ---------- Deploying Server/Server_off env files ----------"
    deploy_server_off_env
    echo "$(date +'%Y/%m/%d %H:%M:%S') Deploy Server/Server_off env files DONE"
    echo "$(date +'%Y/%m/%d %H:%M:%S') ---------- Deploying jvm.options files ----------"
    deploy_jvm_options_file
    echo "$(date +'%Y/%m/%d %H:%M:%S') Deploy jvm.options files DONE"

}

check_exist_directory() {
    dir=$1
    if [ ! -d $dir ]; then
        echo "$(date +'%Y/%m/%d %H:%M:%S') Not found $dir. Creating ... Re-try later"
        mkdir -p $dir
        exit 1
    else
        echo "$(date +'%Y/%m/%d %H:%M:%S') Found $dir"
    fi
        
}

pre_deploy() {
    check_exist_directory $dir_all_needed_files_deployed
    check_exist_directory $dir_war_deploy
}

rollback_war() {
    version=$1

    if [ ! -d "${dir_war}_$version" ]; then
        echo "$(date +'%Y/%m/%d %H:%M:%S') Nothing to rollback version $version. Ignore this step"
    else
        find "${dir_war}_$version" -type f \( -name "*.war_${version}" -o -name "*.jar_${version}" \) -exec sh -c 'echo "$(date +%Y/%m/%d\ %H:%M:%S) Found $(basename $1)"; file_name=$(basename $1); original_file_name="${file_name%_*}";  cp "$1" "$2/$original_file_name"' sh {} "${dir_war}" \;
    fi

}
rollback_jvm() {
    version=$1

    if [ ! -f "${file_jvm_options}_$version" ]; then
        echo "$(date +'%Y/%m/%d %H:%M:%S') Nothing to rollback JVM Options file version $version. Ignore this step"
    else
        echo "$(date +'%Y/%m/%d %H:%M:%S') Copy ${file_jvm_options}_$version to $file_jvm_options"
        cp "${file_jvm_options}_$version" "$file_jvm_options"
    fi
}
rollback_server_off_env() {
    version=$1

    if [ ! -f "${file_server_off_env}_$version" ]; then
        
        echo "$(date +'%Y/%m/%d %H:%M:%S') Nothing to rollback Server/Server_off env file version $version. Ignore this step"
    else
        echo "$(date +'%Y/%m/%d %H:%M:%S') Copy ${file_server_off_env}_$version to $file_server_off_env"
        cp "${file_server_off_env}_$version" "$file_server_off_env"
    fi

}

rollback(){
    version=$1
    rollback_war $version
    rollback_jvm $version
    rollback_server_off_env $version
}

case "$phase" in
    "pre_deploy")
        echo "$(date +'%Y/%m/%d %H:%M:%S') ---------- Pre-Deploying ----------"
        pre_deploy
        echo "$(date +'%Y/%m/%d %H:%M:%S') Pre-Deploy DONE"
        ;;
    "back_up")
        echo "$(date +'%Y/%m/%d %H:%M:%S') ---------- Backing up ----------"
        back_up
        echo "$(date +'%Y/%m/%d %H:%M:%S') Back up DONE"
        ;;
    "deploy")
        echo "$(date +'%Y/%m/%d %H:%M:%S') ---------- Deploying ----------"
        deploy
        echo "$(date +'%Y/%m/%d %H:%M:%S') Your deployment has been SUCCESS"
        ;;
    "rollback")
        version=$2
        echo "$(date +'%Y/%m/%d %H:%M:%S') ---------- Rollbacking to version $version ----------"
        rollback $version
        echo "$(date +'%Y/%m/%d %H:%M:%S') Rollback has been SUCCESS"
        ;;             
    *)        
    *)
        echo "Choose phase: pre_deploy, back_up or deploy"
        ;;
esac
