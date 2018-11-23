#!/bin/bash
# Script to get nsrecords from domain. Used by terraform (data.external). Needs aws and jq installed
# jq retrives the JSON supplied by calling terraform & parses into variables.
eval "$(jq -r '@sh "export hosted_zone=\(.hosted_zone)"')"
# Check to see if required variables are properly received. 
if [[ "${hosted_zone}" == "null" || -z "${hosted_zone}" ]]; then 
    echo -e "Required input [hosted_zone=$hosted_zone]. Seems empty ... Exiting!" 1>&2; exit 1 
fi
# Retrieve the ns records using aws command line and convert the output into text strings. 
nsrecords=$(aws route53 list-resource-record-sets --hosted-zone-id "${hosted_zone}" \
    --output text --query 'ResourceRecordSets[?Type==`NS`].ResourceRecords[*]')
#nsrecords=$(cat ./recs.txt)
#echo -e "$nsrecords" 1>&2
# Creating the JSON for the retrieved nsrecords from the hosted zone 
# TODO: Figure out how to use jq to create a JSON map of strings. 
# Note: in windows bash envs, the nsrecords output includes '\r\n'. So we truncate that
# in each cycle of the loop. The calls to tr do nothing in pure linux envs.
i=1; result="{"
while read line; do
    tmp="\"Value$i\": \"$line\","; result="$result$tmp"; result=$(echo "$result" | tr -d '\n' | tr -d '\r'); ((i++));
done <<< "$nsrecords"
result=${result%*,}; result="$result}"
# JSON map of nsrecords strings created, output it using jq. 
echo -e "$result" | jq .
if(($?)); then echo -e "Error in jq. Exiting." 1>&2; exit 1; fi
