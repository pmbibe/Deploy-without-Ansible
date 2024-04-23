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


helm_path="/home/ducptm/Helm"
module_helm_list=$(ls $helm_path)
ignore_error_directory=('ignore_error_directory_values')

refomart_file_name(){

    fileS=$1
    fileD=$2
    # echo "Move from $fileD to $fileD -- Start"
    for module_helm in $module_helm_list; do
    if [ $module_helm != "DR" ]; then
        if [ ! -f "$helm_path/$module_helm/templates/$fileD" ]; then
            find "$helm_path/$module_helm/" -name "$fileS" -exec mv {} "$helm_path/$module_helm/templates/$fileD" \;
        fi
    fi
    done 
    # echo "Move from $fileD to $fileD -- Done"

}

reformat_blank_space(){

    file=$1
    # echo "Reformat Blank Space $file -- Start"
    for module_helm in $module_helm_list; do
        if [ -f $helm_path/$module_helm/templates/$file ]; then
            sed -i '/^[[:space:]]*$/d' "$helm_path/$module_helm/templates/$file"
        fi
    done    
    # echo "Reformat Blank Space $file -- Done"

}

remove_fullnameOverride(){
    # echo "Remove FullnameOverride -- Start"
    source='fullnameOverride'
    dest='fullnameOverride: ""'
    for module_helm in $module_helm_list; do
        if [ -f "$helm_path/$module_helm/values.yaml" ]; then
            sed -i "/^$source/d" "$helm_path/$module_helm/values.yaml"
            sed -i "\$a$dest" "$helm_path/$module_helm/values.yaml"
        fi
    done   
    # echo "Remove FullnameOverride -- Done"

}

insert_chart_fullname(){
    # echo "Insert Chart Fullname -- Start"
    line_1='{{- else if .Values.deploymentId }}'
    line_2='{{- printf "%s-%s" .Chart.Name (.Values.deploymentId | toString) | trunc 63 | trimSuffix "-" }}'
    find_line='''{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}'''

    for module_helm in $module_helm_list; do

        file="$helm_path/$module_helm/templates/_helpers.tpl"

        if [ -f $file ]; then
            pre_line_result=$(grep -n "$find_line" $file)
            # Use parameter expansion to extract the number before ':'
            line_number=$(($(echo "$pre_line_result" | cut -d ':' -f 1) + 1))

            sed -i "$line_number i $line_2" "$file"
            sed -i "$line_number i $line_1" "$file"

        fi
    done 
    # echo "Insert Chart Fullname -- Done"  

}


insert_config_files(){

    # echo "Insert Config File -- Start" 
    for module_helm in $module_helm_list; do
        if [ -d "$helm_path/$module_helm/files" ] && [[ " ${ignore_error_directory[@]} " != *" $module_helm "* ]]; then
            insert_config_files_by_type "$helm_path/$module_helm/templates/configmaps.yaml"  "jvm.options"
            insert_config_files_by_type "$helm_path/$module_helm/templates/configmaps.yaml" "server.env"
        fi
    done    

    # echo "Insert Config File -- Done" 
}

insert_config_files_by_type(){
    file=$1
    file_type=$2
    # echo "Insert Config File $file by $file_type -- Start" 
    server_env_line="  $file_type: |-"
    line_1="{{- if .Values.deploymentId -}}"
    IFS='.' read -r -a file_type_array <<< "$file_type"
    line_2='{{ .Files.Get (printf "files/'"${file_type_array[0]}"'-%s.'"${file_type_array[-1]}"'" ( .Values.deploymentId | toString)) | nindent 4 }}'
    line_3='{{- else }}'
    line_4='{{- end }}'
    pre_line_result=$(grep -n "$server_env_line" $file)
    line_number=$( echo "$pre_line_result" | cut -d ':' -f 1)
    # echo "$line_number ------- $file"
    sed -i "$(($line_number+1)) i \    $line_1" "$file"
    sed -i "$(($line_number+2)) i $line_2" "$file"
    sed -i "$(($line_number+3)) i \    $line_3" "$file"
    sed -i "$(($line_number+5)) i \    $line_4" "$file"
    # echo "Insert Config File $file by $file_type -- Done" 
}

add_lines_to_helpers_file(){
    fileS=$1
    # echo "Add lines to _helpers.tpl File $fileS -- Start" 
    for module_helm in $module_helm_list; do
    if [  -f "$helm_path/$module_helm/templates/$fileS" ]; then
        # echo "Backup $helm_path/$module_helm/templates/$fileS -- Start"
        cp "$helm_path/$module_helm/templates/$fileS" "$helm_path/$module_helm/templates/$fileS_$(date +'%Y%m%d')"
        # echo "Backup $helm_path/$module_helm/templates/$fileS -- Done"    
cat >> "$helm_path/$module_helm/templates/$fileS" << 'EOF'
{{/*
Activemq URI
*/}}
{{- define "activemq-uri"}}
{{- if .deploymentId }}
{{- printf "%s-%s:61616" .instance (.deploymentId | toString) }}
{{- else }}
{{- printf "%s:61616" .instance }}
{{- end }}
{{- end }}
{{/* 
Eureka your-text URI 
*/}} 
{{- define "your-text-uri"}} 
{{- if .Values.deploymentId}} 
{{- printf "your-text-%s:8761" (.Values.deploymentId | toString)}} 
{{- else }} 
{{- default "your-text:8761" }} 
{{- end }} 
{{- end }} 
EOF
    fi
    done 
    # echo "Add lines to _helpers.tpl File $fileS -- Done" 
}

configmaps_replace(){

    # echo "Configmaps Replace -- Start" 

    for module_helm in $module_helm_list; do
        if [  -f "$helm_path/$module_helm/templates/configmaps.yaml" ]; then
            sed -i 's|your-text:8761|{{ include "your-text-uri" . }}|g' "$helm_path/$module_helm/templates/configmaps.yaml"
            sed -i 's|your-text:61616|{{ include "activemq-uri" (dict "deploymentId" .Values.deploymentId "instance" "your-text") }}|g' "$helm_path/$module_helm/templates/configmaps.yaml"
            sed -i 's|your-text:61616|{{ include "activemq-uri" (dict "deploymentId" .Values.deploymentId "instance" "your-text") }}|g' "$helm_path/$module_helm/templates/configmaps.yaml"
        fi
    done
    # echo "Configmaps Replace -- Done" 
}

deployment_replace(){

    # echo "Deployment Replace -- Start" 

    for module_helm in $module_helm_list; do
        if [  -f "$helm_path/$module_helm/templates/deployment.yaml" ]; then
            sed -i 's|your-text:8761|{{ include "your-text-uri" . }}|g' "$helm_path/$module_helm/templates/deployment.yaml"
        fi
    done

    # echo "Deployment Replace -- Done" 
    
}

vaules_replace(){

    # echo "Values Replace -- Start" 

    for module_helm in $module_helm_list; do
        if [  -f "$helm_path/$module_helm/templates/values.yaml" ]; then
            sed -i 's|your-text:8761|{{ include "your-text-uri" . }}|g' "$helm_path/$module_helm/templates/values.yaml"
        fi
    done

    # echo "Values Replace -- Done" 
}

change_hpa(){

    # echo "Change HPA -- Start"

    for module_helm in $module_helm_list; do
        if [  -f "$helm_path/$module_helm/values.yaml" ]; then

            dos2unix "$helm_path/$module_helm/values.yaml" > /dev/null 2>&1
            modify_min_replicas "$helm_path/$module_helm/values.yaml"
            modify_max_replicas "$helm_path/$module_helm/values.yaml"
        fi
    done

    # echo "Change HPA -- Done"
}

modify_min_replicas() {
    file_path=$1
    # echo "Modify minReplicas HPA file $file_path -- Start"
    while IFS= read -r line; do

        if [[ $line =~ ^[[:space:]]*minReplicas: ]]; then
            
            current_value=$(echo "$line" | awk '{print $2}')
            pre_line_result=$(grep -n "minReplicas:" $file_path)
            line_number=$(echo "$pre_line_result" | cut -d ':' -f 1)

            if [[ $current_value -ge 3 && $current_value -le 4 ]]; then
                sed -i '/^\s*minReplicas:/s/^/#/; ' $file_path
                sed -i "$(($line_number+1)) i \  minReplicas: 2" $file_path                
            elif [[ $current_value -ge 5 && $current_value -le 6 ]]; then
                sed -i '/^\s*minReplicas:/s/^/#/; ' $file_path
                sed -i "$(($line_number+1)) i \  minReplicas: 3" $file_path                
            elif [[ $current_value -gt 10 ]]; then
                sed -i '/^\s*minReplicas:/s/^/#/; ' $file_path
                sed -i "$(($line_number+1)) i \  minReplicas: 5" $file_path
            fi
        fi
    done < "$file_path"

    # echo "Modify minReplicas HPA file $file_path -- Done"

}

modify_max_replicas() {
    file_path=$1
    # echo "Modify maxReplicas HPA file $file_path -- Start"
    while IFS= read -r line; do

        if [[ $line =~ ^[[:space:]]*maxReplicas: ]]; then
            
            current_value=$(echo "$line" | awk '{print $2}')
            pre_line_result=$(grep -n "maxReplicas:" $file_path)
            line_number=$(echo "$pre_line_result" | cut -d ':' -f 1)

            if [[ $current_value -ge 5 && $current_value -le 6 ]]; then
                sed -i '/^\s*maxReplicas:/s/^/#/; ' $file_path
                sed -i "$(($line_number+1)) i \  maxReplicas: 3" $file_path                
            elif [[ $current_value -lt 8 && $current_value -gt 6 ]]; then
                sed -i '/^\s*maxReplicas:/s/^/#/; ' $file_path
                sed -i "$(($line_number+1)) i \  maxReplicas: 4" $file_path                
            elif [[ $current_value -lt 16 && $current_value -gt 8 ]]; then
                sed -i '/^\s*maxReplicas:/s/^/#/; ' $file_path
                sed -i "$(($line_number+1)) i \  maxReplicas: 8" $file_path
            fi
        fi
    done < "$file_path"

    # echo "Modify maxReplicas HPA file $file_path -- Done"

}

change_config_map(){
    ID=$1
    # echo "Change config in server-$ID.env and jvm-$ID.options -- Start"
    for module_helm in $module_helm_list; do
        if [[ -f "$helm_path/$module_helm/files/server.env" ]] && [[ -f "$helm_path/$module_helm/files/jvm.options" ]]; then
            cp $helm_path/$module_helm/files/server.env "$helm_path/$module_helm/files/server-$ID.env"
            cp $helm_path/$module_helm/files/jvm.options "$helm_path/$module_helm/files/jvm-$ID.options"
            # ---------------------------------------------------
            sed -i 's/your-text:8761/your-text-'"$ID"':8761/g' "$helm_path/$module_helm/files/jvm-$ID.options"
            sed -i 's/your-text:8761/your-text-'"$ID"':8761/g' "$helm_path/$module_helm/files/server-$ID.env"
            sed -i 's/your-text:8761/your-text-'"$ID"':8761/g' "$helm_path/$module_helm/values.yaml"
            sed -i 's/your-text:8761/{{ include "your-text-uri" . }}/g' "$helm_path/$module_helm/templates/deployment.yaml"
            sed -i 's/your-text:8761/{{ include "your-text-uri" . }}/g' "$helm_path/$module_helm/templates/configmaps.yaml"
            # ---------------------------------------------------
            sed -i 's/your-text:61616/your-text-'"$ID"':61616/g' "$helm_path/$module_helm/files/server-$ID.env"
            sed -i 's/your-text:61616/your-text-'"$ID"':61616/g' "$helm_path/$module_helm/files/jvm-$ID.options"
            sed -i 's/your-text:61616/{{ include "activemq-uri" (dict "deploymentId" .Values.deploymentId "instance" "your-text") }}/g' "$helm_path/$module_helm/templates/configmaps.yaml"
            # ---------------------------------------------------
            sed -i 's/your-text:61616/your-text-'"$ID"':61616/g' "$helm_path/$module_helm/files/server-$ID.env"
            sed -i 's/your-text:61616/your-text-'"$ID"':61616/g' "$helm_path/$module_helm/files/jvm-$ID.options"            
            sed -i 's/your-text:61616/{{ include "activemq-uri" (dict "deploymentId" .Values.deploymentId "instance" "your-text") }}/g' "$helm_path/$module_helm/templates/configmaps.yaml"
            
            module_helm_options=("dbs_ha_1971.partnerx.9817" "dbs_ha_1971.cards.9201" "dbs_ha_1971.customers.9017" "dbs_ha_1971.savings.9202")
            if [[ " ${module_helm_options[@]} " == *" $module_helm "* ]]; then
                echo "Find and replace -your-text:9 in Module $module_helm -- Start"
                sed -i 's/-your-text:9/-your-text-'"$ID"':9/g' "$helm_path/$module_helm/files/server-$ID.env"
                echo "Find and replace -your-text:9 in Module $module_helm -- Done"
            fi
        fi
    done
    # echo "Change config in server-$ID.env and jvm-$ID.options -- Done"

}

change_edge_service_template(){

    # echo "Change edge service template file -- Start"
    file="$helm_path/your-text/templates/service.yaml"
    sed -i 's/your-text.fullname/your-text.name/g' $file
    sed -i '/{{- include "your-text.labels" . | nindent 4 }}/s/^/#/' $file
    pre_line_result=$(grep -n '{{- include "your-text.labels" . | nindent 4 }}' $file)
    line_number=$(echo "$pre_line_result" | cut -d ':' -f 1)
    sed -i "$(($line_number+1)) i \    app.kubernetes.io/name: {{ include \"your-text.name\" . }}" $file
    # echo "Change edge service template file -- Done"
}

verify_deployment(){
    for module_helm in $(ls $helm_path | grep dbs | grep -v noti.internal); do
        module_helm_options=("module_helm_options_values")
        if [[ " ${module_helm_options[@]} " == *" $module_helm "* ]]; then
            tmp="${module_helm#*.}"
            release_name=$(echo "${tmp%.*}" | tr '.' '-')
            
            helm template "$release_name-2" "$helm_path/${module_helm}" --set deploymentId=2 --debug --dry-run
        fi
    done

}

refomart_file_name "*.tpl" "_helpers.tpl"
refomart_file_name "configmap.yaml" "configmaps.yaml"
reformat_blank_space "_helpers.tpl"
reformat_blank_space "configmaps.yaml"
remove_fullnameOverride
insert_chart_fullname
insert_config_files
add_lines_to_helpers_file "_helpers.tpl"
configmaps_replace
deployment_replace
vaules_replace
change_hpa
change_config_map 2
change_edge_service_template
# echo "----------------------------- Verify Helm -----------------------------"
verify_deployment
# echo "----------------------------- SUCCESS-----------------------------" 
