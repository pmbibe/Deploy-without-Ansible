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

helm_path="/Your/Helm/Path"
module_helm_list=$(ls $helm_path)
ignore_error_directory=('')

add_line_livenessProbe(){

for module_helm in $module_helm_list; do
        if [ -f "$helm_path/$module_helm/templates/deployment.yaml" ]; then
            line="{{- with .Values.healthCheck.livenessProbe }}"
            current_value=$(echo "$line" | awk '{print $2}')
            pre_line_result=$(grep -n "{{- with .Values.healthCheck.livenessProbe }}" "$helm_path/$module_helm/templates/deployment.yaml")
            line_numbers=$(echo "$pre_line_result" | cut -d ':' -f 1)
            readarray -t line_numbers_array <<< "$line_numbers"
            length=${#line_numbers_array[@]}
            for ((i = 0; i < length; i++)); do          
                if [[ ${line_numbers_array[i]} -gt 0 ]]; then   
                    echo "Replace livenessProbe in $helm_path/$module_helm/templates/deployment.yaml"
                    echo "$((${line_numbers_array[i]}))"
                    sed -i "$((${line_numbers_array[i]} - i * 2)) i \          livenessProbe: {{ include "'"livenessProbe"'" . | nindent 12 }}" "$helm_path/$module_helm/templates/deployment.yaml"
                    echo "$((${line_numbers_array[i]}))"
                    echo "Delete Old livenessProbe in $helm_path/$module_helm/templates/deployment.yaml"
                    sed -i "$((${line_numbers_array[i]} + 1 - i * 2))d" "$helm_path/$module_helm/templates/deployment.yaml"
                    sed -i "$((${line_numbers_array[i]} + 1 - i * 2))d" "$helm_path/$module_helm/templates/deployment.yaml"
                    sed -i "$((${line_numbers_array[i]} + 1 - i * 2))d" "$helm_path/$module_helm/templates/deployment.yaml"
                    echo "Delete Old livenessProbe in $helm_path/$module_helm/templates/deployment.yaml -- DONE"                    
                    echo "Replace livenessProbe in $helm_path/$module_helm/templates/deployment.yaml -- DONE"
                fi
            done
        fi
    # fi
done

}

add_lines_to_helpers_file(){
    fileS=$1
    # echo "Add lines to _helpers.tpl File $fileS -- Start" 
    for module_helm in $module_helm_list; do
    if [  -f "$helm_path/$module_helm/templates/$fileS" ]; then   
cat >> "$helm_path/$module_helm/templates/$fileS" << 'EOF'
{{- define "livenessProbe" -}}
timeoutSeconds: 15
initialDelaySeconds: 30
periodSeconds: 30
successThreshold: 1
failureThreshold: 20
exec:
    command:
    - /bin/bash
    - '-c'
    - >-
      if [[ "$(curl -sk http://{{ include "registry-uri" . }}/eureka/apps|grep instanceId)" =~ $HOSTNAME ]]; then exit 0; else exit 1; fi
{{- end }}
EOF
    fi
    done 
    # echo "Add lines to _helpers.tpl File $fileS -- Done" 
}


add_line_livenessProbe
   
add_lines_to_helpers_file "_helpers.tpl"
