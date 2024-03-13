#!/bin/bash
path='/data/hydro-liberty/'
server_off_vars_path="/home/quantri/ducptm/server_off_vars.txt"
module_name=$1
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
    dir_war_backup_path="$path$1/usr/servers/defaultServer/dropins_$(date +'%Y%m%d')"
    dir_war_path="$path$1/usr/servers/defaultServer/dropins"
    find "$dir_war_path" -type f -name "*.war" -exec cp {} "$dir_war_backup_path/$(basename {} .war)_$(date +'%Y%m%d').war" \;
}
back_up_jvm() {
    cp $path$1/usr/servers/defaultServer/jvm.options $path$1/usr/servers/defaultServer/jvm.options_$(date +'%Y%m%d')
}
back_up_server_off_env() {
    cp $path$1/usr/servers/defaultServer/server_off.env $path$1/usr/servers/defaultServer/server_off.env_$(date +'%Y%m%d')
}
get_details_server_off_env() {
    # Initialize variables
    is_the_first=false
    current_action=""
    declare -A dict_action
    declare -a list_action
    if [ -f "$server_off_vars_path" ]; then
        # Read the file line by line
        while IFS= read -r line; do
            # Check if the line matches the pattern and it's not the first variable
            if [[ $line =~ --\ ([[:alnum:]]+) && ! $is_the_first ]]; then
                action="${line:3}"
                echo $action
                # Check if the action is not in the list_action
                if [[ ! " ${list_action[@]} " =~ " $action " ]]; then 
                    list_action+=("$action")
                    dict_action["$action"]=()
                    current_action="$action"
                fi
                is_the_first=true
            # Check if the line is "--" and it's the first variable
            elif [[ $line = "--" && $is_the_first ]]; then
                is_the_first=false
            # Check if it's the first variable
            elif $is_the_first; then
                dict_action["$current_action"]+=("$line")
            fi
        done < $server_off_vars_path
    else
        echo "File not found: $server_off_vars_path"
    fi

    echo $dict_action
    echo $list_action

    # Print dict_action
    for key in "${!dict_action[@]}"; do
        echo "Key: $key"
        for value in "${dict_action[$key]}"; do
            echo "Value: $value"
        done
    done

}

# update_server_off_env() {

# }

# insert_server_off_env() {
    
# }

test() {
    declare -a list_action
    declare -A dict_action

    if [ -f "$server_off_vars_path" ]; then
        # Read the file line by line
        while IFS= read -r line; do
            trimmed_line="${line#"${line%%[![:space:]]*}"}"
            trimmed_line="${trimmed_line%"${trimmed_line##*[![:space:]]}"}"
            if [[ $line =~ --\ ([[:alnum:]]+) && ! $is_the_first ]]; then
                action="${line:3}"
                if [[ ! " ${list_action[@]} " =~ " $action " ]]; then 
                    list_action+=("$action")
                    dict_action["$action"]=[]
                    current_action="$action"
                fi
                echo "Change is_the_first = true"
                is_the_first=true
            # Check if the line is "--" and it's the first variable
            elif [[ $trimmed_line = "--" && $is_the_first ]]; then
                echo "Change is_the_first = false"
                is_the_first=false
            # Check if it's the first variable
            elif $is_the_first; then
                echo "$line"
                dict_action["$current_action"]+=["$line"]
            fi
        done < $server_off_vars_path

    fi
    # echo $list_action
    # echo $dict_action
}

test1() { 
    if [ -f "$server_off_vars_path" ]; then
        # Read the file line by line
        while IFS= read -r line; do
            echo $line
            trimmed_line="${line#"${line%%[![:space:]]*}"}"
            trimmed_line="${trimmed_line%"${trimmed_line##*[![:space:]]}"}"
            if [[ "$trimmed_line" == "--" ]]; then
                echo "Change is_the_first = false"
            # Check if it's the first variable
            fi
        done < $server_off_vars_path

    fi
}
test

# get_details_server_off_env
