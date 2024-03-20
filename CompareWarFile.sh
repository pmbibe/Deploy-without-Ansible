#!/bin/bash

while [[ $# -gt 0 ]]; do
    case "$1" in
        -sa | --server-a)
            shift
            server_a="$1"
            ;;
        -sb | --server-b)
            shift
            server_b="$1"
            ;;
        -sp | --serive-port)
            shift
            service_port="$1"
            ;;
        *)
            echo "Invalid option: $1"
            exit 1
            ;;
    esac
    shift
done

declare -a all_servers=('','','')
list_module_full_file="./listModuleFull.txt"
service_path="/data/pmbibe/ducptm_service/"
special_services=('A.9020' 'B.9330')
validated_port_list=()
md5_file_list=()
username='ducptm'

get_md5_file() {
    username=$1
    hostname=$2
    module_path=$3
    ssh $username@$hostname find "$module_path/usr/servers/defaultServer/dropins" -type f \( -name "*.war" -o -name "*.jar" \) -execdir md5sum {} \;
    for element in "${result[@]}"; do
        md5_file_list+=("$element")
    done
}

prep_process() {
    username=$1
    hostname=$2
    module_path=$3
    local -A dict
    get_md5_file $username $hostname $module_path
    for element in "${md5_file_list[@]}"; do
        read -ra arr <<<"$element"
        dict["${arr[-1]##*/}"]+="${arr[0]}"
    done
    echo '('
    for key in  "${!dict[@]}" ; do
        echo "[$key]=${dict[$key]}"
    done    
    echo ')'
}

compare_file() {
    local -A md5_war_file_host_1=$1
    local -A md5_war_file_host_2=$2

    are_equal=true

    if [ ${#md5_war_file_host_1[@]} -eq ${#md5_war_file_host_2[@]} ]; then
        for key in ${!md5_war_file_host_1[@]}; do
            if [ $md5_war_file_host_1[$key] != $md5_war_file_host_2[$key] ]; then
                are_equal=false
                break
            fi
        done
    else
        are_equal=false
    fi
    
    echo $are_equal
}

compare_war_file_multiple_servers() {
    username=$1
    module_path=$2
    local -a list_servers=("${@:3}")
    are_equal=true
    list_servers_count=${#list_servers[@]}
    # Iterate over the indices of the array
    for ((i = 0; i < $list_servers_count - 1; i++)); do
        are_equal=$(compare_file "$(prep_process $username ${list_servers[i]} $module_path)" "$(prep_process $username ${list_servers[i+1]} $module_path)")
    done
    if ($are_equal) then
        echo "------------------- Equal -------------------"
    else
        echo "------------------- NOT Euqal -------------------"
    fi
    
}


get_service_by_port() {
    username=$username
    hostname='127.0.0.1'
    echo "ssh $username@$hostname 'ls ${service_path}'" >> $list_module_full_file
}

get_validate_port() {
    local -a list=("${@}")
    for service_and_port in ${list[@]}; do
        if [[ $service_and_port =~ \.[0-9]+$ ]]; then
            IFS='.' read -r -a service_and_port_array <<< "$service_and_port"
            port=${service_and_port_array[-1]}
            validated_port_list+=("$port")
        fi
    done
}

exit_handler() {
    local exit_code="$?"
    if [ $exit_code -ne 0 ]; then
        echo "Error: Script encountered an error. For more details, please contact ducptm@tpb.com.vn" >&2
    fi
    exit $exit_code
}

trap exit_handler EXIT

if [ ! -f "$list_module_full_file" ]; then
    echo "It seems to be the first time you're running this script. Please wait a moment to get the list of modules"
    get_service_by_port
fi

readarray -t list_services <<< "$(cat $list_module_full_file)"

all_list_services=("${list_services[@]}" "${special_services[@]}")

get_validate_port "${all_list_services[@]}"

load_config_module_file() {
    for service_and_port in ${special_services[@]}; do
        if [[ $service_and_port =~ \.[0-9]+$ ]]; then
            IFS='.' read -r -a service_and_port_array <<< "$service_and_port"
            port=p_${service_and_port_array[-1]}
            service_name=$(IFS='.'; echo "${service_and_port_array[*]:0:${#service_and_port_array[@]}-1}")
            eval "$port=\"$service_name\""
        fi
    done

    for service_and_port in ${list_services[@]}; do
        if [[ $service_and_port =~ \.[0-9]+$ ]]; then
            IFS='.' read -r -a service_and_port_array <<< "$service_and_port"
            port=p_${service_and_port_array[-1]}
            service_name=$(IFS='.'; echo "${service_and_port_array[*]:1:${#service_and_port_array[@]}-2}")
            eval "$port=\"$service_name\""
            
             
        fi
    done

}

load_config_module_file

if [[ ! ( "$service_port" && "$service_port" =~ ^[0-9]+$ ) || ! "${validated_port_list[@]}" =~ (^|[[:space:]])"${service_port}"($|[[:space:]]) || "$service_port" == "All" ]]; then
    echo "You need PortService parameter"
    echo "Choose one of the ports to deploy modules correspondingly."
    for service_and_port in ${all_list_services[@]}; do
        if [[ $service_and_port =~ \.[0-9]+$ ]]; then
            IFS='.' read -r -a service_and_port_array <<< "$service_and_port"
            port=p_${service_and_port_array[-1]}
            echo "    $port --- ${!port}"
        fi
    done
    retry_count=3
    for ((i = 1; i < $retry_count + 1; i++)); do
        if [[ ! ( "$service_port" && "$service_port" =~ ^[0-9]+$ )  || ! "${validated_port_list[@]}" =~ (^|[[:space:]])"${service_port}"($|[[:space:]]) ]]; then
            echo -n "Please enter the port for your service: "
            read service_port
        fi
        if [[ (! ( "$service_port" && "$service_port" =~ ^[0-9]+$ ) || ! "${validated_port_list[@]}" =~ (^|[[:space:]])"${service_port}"($|[[:space:]])) && ($retry_count-$i -ne 0) ]]; then
            echo "Invalid port. Remaining $((retry_count - i)) attempts"
        fi
    done
fi

if [[  ( "$service_port" && "$service_port" =~ ^[0-9]+$ ) &&  "${validated_port_list[@]}" =~ (^|[[:space:]])"${service_port}"($|[[:space:]]) || "$service_port" == "All" ]]; then
    if [[ "$service_port" == "All" ]]; then
        source_path="/data/pmbibe/ducptm_service/"
        for service_and_port in ${list_services[@]}; do
            if [[ $service_and_port =~ \.[0-9]+$ ]]; then
                compare_war_file_multiple_servers "$username" "${sourcePath}${ServiceAndPort}" "${all_servers[@]}"
            fi
        done
        source_path="/data/pmbibe/"
        for service_and_port in ${special_services[@]}; do
            if [[ $service_and_port =~ \.[0-9]+$ ]]; then
                compare_war_file_multiple_servers "$username" "${sourcePath}${ServiceAndPort}" "${all_servers[@]}"
            fi
        done
    else
        
        p_service_port=p_${service_port}
        service_name=${!p_service_port}
        case "$service_port" in
            "9020")
                source_path='/data/pmbibe'
                module_name="${service_name}.${service_port}"
                echo $module_name
                ;;
            "9330")
                source_path='/data/pmbibe'
                module_name="${service_name}.${service_port}"
                echo $module_name
                ;;
            *)
                source_path='/data/pmbibe/ducptm_service'
                module_name="ducptm.${service_name}.${service_port}"
                echo $module_name                
                ;;
        esac
        compare_war_file_multiple_servers "$username" "${source_path}/${module_name}" "${all_servers[@]}"
    fi
fi
