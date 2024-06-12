#!/usr/bin/bash

#sets the current working directory variable to the working script, the directory path is then retrieved by the script. 
#variable cf is then set to the cloud foundry file, the path is then added to the file.
#the file path is then checked to see if it exists
cwd=$(dirname $0)
cf="credentials.cf"
config="$cwd/$cf"
[ -f "$config" ] && source "$config"

#creation variables
atlantisFile="atlantis.yaml"
terraformRoleName="terraform"
repoName="awscontainerservice"
mainBranch="main"
region="us-west-2"
startPath="."
baseStateBucketName="terraform-state-file"
ignoreGitMain=false
templateProjectName="template-folder"

#get aws profile
fetchProfile() {
  region=$(grep -A3 -w $AWS_PROFILE ~/.aws/config | tail -1 | awk -F\= '{print$2}')
  AWS_REGION=$region
  echo $AWS_REGION
}

# check for requirements
binCheck() {
  for i in "$@"; do
    local BIN_TO_CHECK="$i"; shift
    if [ -z "$(command -v "$BIN_TO_CHECK")" ]; then echo "ERROR: $BIN_TO_CHECK is not installed in your path." && exit 1; fi
  done
}

# check for git directory and branch
gitCheck() {
  git -C "$(pwd)" rev-parse

  if [ $? -ne 0 ]; then
    printf "\\nChange directory in to the '%s' repo ...\\n" "$repoName"
    printf "Exiting.\\n"
    exit 1
  fi

  # check for ignore flag
  [ "$1" == "-i" ] && ignoreGitMain=true

  branch="$(git rev-parse --abbrev-ref HEAD)"

  if [ "$branch" == "$mainBranch" ]; then
    if [ $ignoreGitMain == false ]; then
      printf "\\nYou cannot be on the '%s' branch when running this script.\\n" "$mainBranch"
      printf "\\nRun the following commands to create a local and remotely synced branch.\\n"
      printf "\\ngit checkout -b <youname>/bootsrap_<project>\\n"
      printf "\\ngit push origin -u <youname>/bootsrap_<project>\\n"
      printf "Exiting.\\n"
      exit 1
    fi
  fi
}

# input handleing
handleInputs() {

  # help and usage
  [ "$1" == "--help" ] || [ "$1" == "-h" ] && usage

  [ -n "$AWS_REGION" ] && { validInput=true; region="$AWS_REGION"; validateInputs "$region" "region"; } || validInput=false
  while [ $validInput == false ]; do
    printf "\\nPlease enter the AWS region.\\n"
    read -r userInput
    printf "...\n"
    region="$userInput"
    validateInputs "$region" "region"
  done

    ## project name
  [ -n "$PROJECT_NAME" ] && { validInput=true; name="$FOLDER_NAME"; validateInputs "$name" "all"; } || validInput=false
  while [ $validInput == false ]; do
    printf "\\nPlease enter the new folder name.\\n"
    read -r userInput
    printf "...\n"
    name="$userInput"
    validateInputs "$name" "all"
  done

  ## cidrs private
  [ -n "$CIDR_PRIV" ] && { validInput=true; cidr_priv="$CIDR_PRIV"; validateInputs "$cidr_priv" "cidr"; } || validInput=false
  while [ $validInput == false ]; do
    printf "\\nPlease enter the private cidrs.\\n"
    printf "example value: 10.1.0.0/19,10.1.32.0/19"
    read -r userInput
    printf "...\n"
    cidr_priv="$userInput"
    validateInputs "$cidr_priv" "cidr"
  done
  cidr_priv_tf=$(echo "$cidr_priv" | ${_sed} 's#,#", "#g')
  cidr_priv_tf='["'$cidr_priv_tf'"]'

  ## cidrs public
  [ -n "$CIDR_PUB" ] && { validInput=true; cidr_pub="$CIDR_PUB"; validateInputs "$cidr_pub" "cidr"; } || validInput=false
  while [ $validInput == false ]; do
    printf "\\nPlease enter the public cidrs.\\n"
    printf "example value: 10.1.128.0/20,10.1.144.0/20"
    read -r userInput
    printf "...\n"
    cidr_pub="$userInput"
    validateInputs "$cidr_pub" "cidr"
  done
  cidr_pub_tf=$(echo "$cidr_pub" | ${_sed} 's#,#", "#g')
  cidr_pub_tf='["'$cidr_pub_tf'"]'


  ## cidrs vpc
  [ -n "CIDR_VPC" ] && { validInput=true; cidr_vpc="$CIDR_VPC"; validateInputs "$cidr_vpc" "cidr"; } || validInput=false
  while [ $validInput == false ]; do
    printf "\\nPlease enter the  vpc cidrs.\\n"
    printf "example value: 10.1.0.0/16"
    read -r userInput
    printf "...\n"
    cidr_vpc="$userInput"
    validateInputs "$cidr_vpc" "cidr"
  done
  cidr_vpc_tf='"'$cidr_vpc'"'
}

validateInputs() {
  input="$1"
  checks="$2"

  if [ -z "$input" ]; then
    printf "\\nThe input cannot be blank.\\n"
    validInput=false
    return
  fi

  if [[ "$input" =~ [\ ] ]]; then
    printf "The input '%s' contains spaces which is invalid.\\n" "$input"
    validInput=false
    return
  fi

  # Check cidr
  REGEX='(((25[0-5]|2[0-4][0-9]|1?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9][0-9]?))(\/([8-9]|[1-2][0-9]|3[0-2]))([^0-9.]|$)'

  if [ "$checks" == "cidr" ]; then
   check_cidr() {
      if [[ $1 =~ $REGEX ]]; then
        validCidr="true"
      else
          printf "The input '%s' is not a valid cidr.\\n" "$input"
          validInput=false
          return
      fi
    }
    case "$input" in
      *,*) for i in $(echo "$input" | awk -F\, '{print$1" "$2" "$3}')
           do
             check_cidr "$i"
           done
           ;;
        *) check_cidr "$input" ;;
    esac
  fi

  # Check region
  if [ "$checks" == "region" ]; then
    for i in "${availRegions[@]}"; do
      if [ "$i" == "$input" ]; then
        validRegion="true"
        break
      fi
    done
    if [ "$validRegion" != "true" ]; then
      printf "The input '%s' is not an available AWS region.\\n" "$input"
      validInput=false
      return
    fi
  fi

  if [ "$checks" == "env" ]; then
    for i in "${validEnvs[@]}"; do
      if [ "$i" == "$input" ]; then
        validEnv="true"
        break
      fi
    done
      if [ "$validEnv" != "true" ]; then
      printf "The input '%s' is not a valid environment.\\n" "$input"
      validInput=false
      return
    fi
  fi

  if [ "$checks" == "num" ]; then
    if [[ "$input" =~ [^0-9-] ]]; then
      printf "The input '%s' contains invalid characters, use only numbers.\\n" "$input"
      validInput=false
      return
    fi

    if [ "${#input}" -lt 10 ]; then
      printf "The input '%s' is too short for an AWS id.\\n" "$input"
      validInput=false
      return
    fi
  fi

  if [ "$checks" == "under" ]; then
    if [[ "$input" =~ [^a-zA-Z0-9-_] ]]; then
      printf "The input '%s' contains invalid characters.\\n" "$input"
      validInput=false
      return
    fi
  fi

  if [ "$checks" == "bool" ]; then
    if [ "$input" != "true" ] && [ "$input" != "false" ]; then
      printf "Only 'true' or 'false' accepted.\\n" "$input"
      validInput=false
      return
    fi
  fi

  if [ "$checks" == "all" ]; then
    if [[ "$input" =~ ^[^a-zA-Z] ]]; then
      printf "The input '%s' contains invalid starting character, must begin with a letter.\\n" "$input"
      validInput=false
      return
    fi

    if [[ "$input" =~ [^a-zA-Z0-9-] ]]; then
      printf "The input '%s' contains invalid characters.\\n" "$input"
      validInput=false
      return
    fi

    if [[ "$input" =~ [^[:lower:]-] ]]; then
      printf "The input '%s' contains invalid characters, use lowercase letters.\\n" "$input"
      validInput=false
      return
    fi

    if [ "${#input}" -gt 35 ]; then
      printf "The input '%s' is too long, it must be 35 characters or fewer.\\n" "$input"
      validInput=false
      return
    fi
  fi

  validInput=true
}

confirmInputs() {
  printf "\\nConfirm these values are correct.\\n"
  printf "The AWS_PROFILE ='%s'.\\n" "$AWS_PROFILE"
  printf "The AWS_REGION ='%s'.\\n" "$region"
  printf "The intra cidrs are='%s'.\\n" "$cidr_intra_tf"
  printf "The private cidrs are='%s'.\\n" "$cidr_priv_tf"
  printf "The public cidrs are='%s'.\\n" "$cidr_pub_tf"
  printf "The vpc cidr is='%s'.\\n" "$cidr_vpc_tf"
  
  printf "Only the values of 'YES|yes' will be accepted: "

  read -r userInput
  if [ "$userInput" != "YES" ] && [ "$userInput" != "yes" ] ; then
    printf "Exiting.\\n"
    exit 1
  fi
}

eipCheck() {
  valid_eipCheck=false

  # Get current EIP quota limit
  eipLimit=$( aws-vault exec $AWS_PROFILE -- aws service-quotas get-service-quota \
  --service-code ec2 --quota-code $eipQuotaCode --region "$region" --query 'Quota.Value')

  # Get current EIP in use
  eipUsage=$( aws-vault exec $AWS_PROFILE -- aws ec2 describe-addresses \
  --region "$region" --query 'Addresses[].PublicIp' | jq '. | length')

  # get EIPs available
  eipAvailable=$((${eipLimit%%.*}-${eipUsage%%.*}))

  # if there is less available then we need
  if [ "$eipAvailable" -lt "$eipRequired" ]; then
    printf "\\nThe EC2-VPC Elastic IP current quota limit of '%s' is too low for a new env '%s'. Up the limit by at least '%s' in the region '%s'. Quota code='%s'\\n" \
    "$eipLimit" "$environment" "$eipRequired" "$region" "$eipQuotaCode"
  else
    valid_eipCheck=true
  fi
}


igwCheck() {
  valid_igwCheck=false

  # Get current IGW quota limit
  igwLimit=$( aws-vault exec $AWS_PROFILE -- aws service-quotas get-service-quota \
  --service-code vpc --quota-code $igwQuotaCode --region "$region" --query 'Quota.Value')

  # Get current IGW in use
  igwUsage=$( aws-vault exec $AWS_PROFILE -- aws ec2 describe-internet-gateways \
    --region "$region" --query 'InternetGateways[].InternetGatewayId' | jq '. | length')

  # get IGW available
  igwAvailable=$((${igwLimit%%.*}-${igwUsage%%.*}))

  # if there is less available then we need
  if [ "$igwAvailable" -lt "$igwRequired" ]; then
    printf "\\nThe IGWs per Region current quota limit of '%s' is too low for a new env '%s'. Up the limit by at least '%s' in the region '%s'. Quota code='%s'\\n" \
    "$igwLimit" "$environment" "$igwRequired" "$region" "$igwQuotaCode"
  else
    valid_igwCheck=true
  fi
}

natCheck() {
  valid_natCheck=false

  # Get current NAT quota limit
  natLimit=$( aws-vault exec $AWS_PROFILE -- aws service-quotas get-service-quota \
  --service-code vpc --quota-code $natQuotaCode --region "$region" --query 'Quota.Value')

  # Get current NAT in use
  natUsage=$( aws-vault exec $AWS_PROFILE -- aws ec2 describe-nat-gateways \
    --region "$region" --query 'NatGateways[].NatGatewayId' | jq '. | length')

  # get NAT available
  natAvailable=$((${natLimit%%.*}-${natUsage%%.*}))

  # if there is less available then we need
  if [ "$natAvailable" -lt "$natRequired" ]; then
    printf "\\nThe NATs per Availability zone current quota limit of '%s' is too low for a new env '%s'. Up the limit by at least '%s' in the region '%s'. Quota code='%s'\\n" \
    "$natLimit" "$environment" "$natRequired" "$region" "$natQuotaCode"
  else
    valid_natCheck=true
  fi
}


vpcCheck() {
  valid_vpcCheck=false

  # Get current VPC quota limit
  vpcLimit=$( aws-vault exec $AWS_PROFILE -- aws service-quotas get-service-quota \
  --service-code vpc --quota-code $vpcQuotaCode --region "$region" --query 'Quota.Value')

  # Get current VPC in use
  vpcUsage=$( aws-vault exec $AWS_PROFILE -- aws ec2 describe-vpcs \
    --region "$region" --query 'Vpcs[].VpcId' | jq '. | length')

  # get VPC available
  vpcAvailable=$((${vpcLimit%%.*}-${vpcUsage%%.*}))

  # if there is less available then we need
  if [ "$vpcAvailable" -lt "$vpcRequired" ]; then
    printf "\\nThe VPCs per Region current quota limit of '%s' is too low for a new env '%s'. Up the limit by at least '%s' in the region '%s'. Quota code='%s'\\n" \
    "$vpcLimit" "$environment" "$vpcRequired" "$region" "$vpcQuotaCode"
  else
    valid_vpcCheck=true
  fi
}

createStateBucket() {
  # check if bucket exists first
   aws-vault exec $AWS_PROFILE -- aws s3api list-buckets | grep "terraform-state-file" > /dev/null 2>&1

  if [ $? -ne 0 ]; then
    ## bucket not found
    # create the s3 bucket to use for the remote state.
    # things like versioning and encryption will be added later via the template project terraform
    printf "\\nCreating state bucket...\\n"

    # use LocationConstraint
    if [ "$region" == "us-west-2" ]; then
      constraint=""
    else
      constraint="--create-bucket-configuration LocationConstraint="\"$region"\""
    fi

     aws-vault exec $AWS_PROFILE -- aws s3api create-bucket \
    --bucket="terraform-state-file" $constraint > /dev/null 2>&1
  else
     printf "\\nAn existing terraform state bucket with the same name was found, skipping bucket creation...\\n"
  fi

  if [ $? -eq 0 ]; then
    printf "\\nBucket setup done for bucket with ARN:'%s'.\\n" "arn:aws:s3:::terraform-state-file"
  else
    printf "\\nSomething went wrong creating the bucket. Exiting...\\n"; exit 1
  fi
}

projectDirCheck() {
  ## check repo dir
  if [ -d "${startPath}/project/${name}" ]; then
    printf "The directory '%s/%s/%s' already exists.\\n" "$name"
    exit 1
  fi
}

createFromTemplate() {
  printf "\\nNew folder created.\\n"
  destPath="${startPath}/project/${name}/"
  mkdir -p $destPath
  cp -r "${startPath}/${templateProjectName}"/* "$destPath"/

  if [ -z "$roleArn" ]; then
    roleArn="arn:aws:iam::103565356570:role/terraform"
  fi
  roleArn=${roleArn//\"}

  ## replacements
  ${_sed} -i -e "s#<STATEBUCKET>#${baseStateBucketName}#g" \
             -e "s#<NAME>#${name}#g" \
             -e "s#<REGION>#${region}#g" \
             -e "s#<ROLEARN>#${roleArn}#g" \
             -e "s#<ENVIRONMENT>#${environment}#g" \
             -e "s#\"<CIDR_PRIV_TF>\"#${cidr_priv_tf}#g" \
             -e "s#\"<CIDR_PUB_TF>\"#${cidr_pub_tf}#g" \
             -e "s#\"<CIDR_VPC_TF>\"#${cidr_vpc_tf}#g" \
                "$destPath"/*.tf
}

checkAtlantis() {
  if grep -Fxq "  - name: $name" $atlantisFile; then
    printf "The project '%s-%s' already exists in %s file.\\n" "$name" "$atlantisFile"
    printf "Exiting.\\n"
    exit 1
  fi
}

addAtlantis() {
  printf "\\nAdding config to '%s'.\\n" $atlantisFile

  printf "\\n" >> $atlantisFile
  printf "  - name: %s\\n" $name >> $atlantisFile
  printf "    dir: %s\\n" "$destPath" >> $atlantisFile
  printf "    terraform_version: %s\\n" $terraformVersion >> $atlantisFile
  printf "    autoplan:\\n" >> $atlantisFile
  printf "      when_modified: [\"*.tf\", \"*.tftpl\", \"../modules/**/*.tf\"]\\n" >> $atlantisFile
  printf "      enabled: true\\n" >> $atlantisFile
  printf "    apply_requirements: [mergeable]\\n" >> $atlantisFile

  printf "\\nAtlantis config done. \\n"
}

finish() {
  printf "\\ncomplete.\\n"
  printf "Run the following:\n"
  printf "git add ./\\n"
  printf "git commit -m \"Change: Add new project\"\\n"
  printf "git push\\n"
}

## main func
main() {
  fetchProfile
  binCheck aws jq git
  gitCheck "$@"
  handleInputs "$@"
  confirmInputs "$@"
  createStateBucket
  createFromTemplate
  addAtlantis
  finish
}

# execute main wil all inputs
main "$@"
