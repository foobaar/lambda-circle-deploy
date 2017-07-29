#!/bin/bash

# more bash-friendly output for jq
JQ="jq --raw-output --exit-status"

bold="\e[1m"
dim="\e[2m"
underline="\e[4m"
blink="\e[5m"
reset="\e[0m"
red="\e[31m"
green="\e[32m"
blue="\e[34m"

success() {
  printf "${green}✔ %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}
error() {
  printf "${red}${bold}✖ %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}
note() {
  printf "\n${bold}${blue}Note:${reset} ${blue}%s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}

# Exit on any error
set -e

while [[ $# -gt 1 ]]
do
key="$1"

case $key in
    --env)
    environment="$2"
    shift
    ;;
    --function_name)
    function_name="$2"
    shift
    ;;
    --test_data)
    test_data="$2"
    shift
    ;;
    *)
    error "unknown argument: $key"
    ;;
esac
shift
done

configure_aws_cli(){
    note "configure_aws_cli"
    aws --version
    aws configure set aws_access_key_id ${AWS_ACCESS_KEY_ID}    
    aws configure set aws_secret_access_key ${AWS_SECRET_ACCESS_KEY}
    aws configure set default.region ${AWS_REGION}
    aws configure set default.output json
    success "aws cli successfully configured $(aws --version 2>&1)"
}

create_lambda_package(){
    note "create_lambda_package"
    rm -rf node_modules/
    npm install --production
    # this is done to create a smaller sized zip file.
    zip -r ${function_name}.zip node_modules/ package.json src/ index.js
    success "${function_name}.zip package created..."

}

push_lambda_update() {
    note "list existing versions..."
    aws lambda list-versions-by-function --function-name ${function_name}
    note "push_lambda_update..."
    aws lambda update-function-code --function-name ${function_name} --zip-file fileb://${function_name}.zip
    success "update pushed..."
}

set_environment_variables() {
    note "set env variables..."
    prefix="APP_"
    allEnvVariables=""
    for OUTPUT in $(compgen -A variable | grep "APP_")
    do
        envKey=${OUTPUT#$prefix}
        envValue=${!OUTPUT}
        allEnvVariables="${allEnvVariables}${OUTPUT#$prefix}=${!OUTPUT},"
    done
    #remove trailing comma
    allEnvVariables=${allEnvVariables%$","}
    note "all env variables: ${allEnvVariables}"
    aws lambda update-function-configuration --environment "Variables={${allEnvVariables}}" --function-name ${function_name}
}

test_lambda_update() {
    echo "test_lambda_update"

    aws lambda invoke \
        --function-name ${function_name} \
        --invocation-type RequestResponse \
        --payload "'${test_data}'" \
        outputfile.txt
	
    success "lambda invoked successfully"
}

create_version_and_switch_alias() {
    note "publishing new version..."
    NEW_VERSION=$(aws lambda publish-version --function-name ${function_name} --description ${CIRCLE_SHA1} | jq -r '.Version')
    note "new version published. Version: ${NEW_VERSION}"

    note "update alias for: ${environment^^} to point to version: ${NEW_VERSION}"
    aws lambda update-alias --function-name ${function_name} --function-version ${NEW_VERSION} --name ${environment^^}

    note "get function information after deploy..."
    aws lambda get-function --function-name ${function_name} --qualifier ${environment^^}

    success "lambda update successful..."
}


configure_aws_cli
create_lambda_package
push_lambda_update
set_environment_variables
test_lambda_update
create_version_and_switch_alias
