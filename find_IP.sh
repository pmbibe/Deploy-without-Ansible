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

find_server_env() {
    local path=$1
    find $path -type f -name server.env #server.env
}
get_ip_address() {
    local file=$1

    cat $file | grep -v '^#' |  grep -Eo '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'    
}



declare -A dict_ip_address
ip_information_file="/Your/IP/Information/File/Path"


pre_process(){
    local line=$line
    trimmed_line="${line#"${line%%[![:space:]]*}"}"
    trimmed_line="${trimmed_line%"${trimmed_line##*[![:space:]]}"}"
    echo $trimmed_line
}


replace_ip() {
    local f_ip=$1 #IP need to be replaced
    local r_ip=$2 #IP replace
    local file=$3

    # Search for the IP address in the file and store the line numbers in the array
    mapfile -t get_line < <(grep -n "$f_ip" "$file" | cut -d ':' -f 1)

    # Check if any lines containing the IP were found
    if [[ ${#get_line[@]} -gt 0 ]]; then
        # Concatenate the line numbers into a single string
        lines_string=$(IFS=', '; echo "${get_line[*]}")
		echo "$f_ip was found on $lines_string in $file"
		echo "Replacing $f_ip --> $r_ip"
		sed -i "s|$f_ip|$r_ip|g" $file
		echo "Replaced"
        
    fi

}

ip_information(){
    if [ -f "$ip_information_file" ]; then
        while IFS= read -r line; do
            processed_line=$(pre_process $line)
            IFS=" --> " read -ra value_arr <<< "${processed_line}"
            dict_ip_address["${value_arr[0]}"]+="${value_arr[3]}"
        done < $ip_information_file
    else
        echo "Not Found"
    fi
}

declare -a list_parent_path=('/Your/Parent/Path/')


ip_information

for path in ${list_parent_path[@]}; do

    list_server_env_path=$(find_server_env $path)

    for file in ${list_server_env_path[@]}; do
        for key in "${!dict_ip_address[@]}"; do
			# $key IP replace 2
			# "${dict_ip_address[$key]}" IP need to be replaced 1
            replace_ip "${dict_ip_address[$key]}" $key $file
        done
    done
done
