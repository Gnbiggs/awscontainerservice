#!/usr/bin/bash

#sets the current working directory variable to the working script, the directory path is then retrieved by the script. 
#variable cf is then set to the cloud foundry file, the path is then added to the file.
#the file path is then checked to see if it exists
cwd=$(dirname $0)
cf="credentials.cf"
config="$cwd/$cf"
[ -f "$config" ] && source "$config"

#start altantis server locally
atlantis server \
--atlantis-url="$URL" \
--gh-user="$USERNAME" \
--gh-token="$TOKEN" \
--gh-webhook-secret="$SECRET" \
--repo-allowlist="$REPO_ALLOWLIST"