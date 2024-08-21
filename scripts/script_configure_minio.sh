#!/bin/bash

ACCESS_KEY="minioadmin"
SECRET_KEY="minioadmin"
REGION="eu-west-3"
MINIO_SERVER_URL="https://minio-api-demo-project.apps.cluster-qqr42.qqr42.sandbox592.opentlc.com"


BUCKET="minio-tech-docs"
FILE_PATH="./configurations/data/minio-default-data/a_tech_doc.md"
OBJECT_URL="${MINIO_SERVER_URL}/$BUCKET/a_tech_doc.md"


DATE=$(date -u +"%Y%m%dT%H%M%SZ")
DATE_ONLY=$(date -u +"%Y%m%d")
SERVICE="s3"
ALGORITHM="AWS4-HMAC-SHA256"
SIGNED_HEADERS="host;x-amz-date"

# Taken from http://danosipov.com/?p=496
function sign {
  kSecret=$(printf "AWS4$1" | xxd -p -c 256)
  kDate=$(printf "$2" | openssl dgst -binary -sha256 -mac HMAC -macopt hexkey:$kSecret | xxd -p -c 256)
  kRegion=$(printf "$3" | openssl dgst -binary -sha256 -mac HMAC -macopt hexkey:$kDate | xxd -p -c 256)
  kService=$(printf "$4" | openssl dgst -binary -sha256 -mac HMAC -macopt hexkey:$kRegion | xxd -p -c 256)
  kSigning=$(printf "aws4_request" | openssl dgst -binary -sha256 -mac HMAC -macopt hexkey:$kService | xxd -p -c 256)
  printf $kSigning
}

# URI Parser taken from https://gist.github.com/leesei/6668590
function uri_parser() {
    # uri capture
    uri="$@"

    # safe escaping
    uri="${uri//\`/%60}"
    uri="${uri//\"/%22}"

    # top level parsing
    pattern='^(([a-z]{3,5})://)?((([^:\/]+)(:([^@\/]*))?@)?([^:\/?]+)(:([0-9]+))?)(\/[^?]*)?(\?[^#]*)?(#.*)?$'
    [[ "$uri" =~ $pattern ]] || return 1;

    # component extraction
    uri=${BASH_REMATCH[0]}
    uri_schema=${BASH_REMATCH[2]}
    uri_address=${BASH_REMATCH[3]}
    uri_user=${BASH_REMATCH[5]}
    uri_password=${BASH_REMATCH[7]}
    uri_host=${BASH_REMATCH[8]}
    uri_port=${BASH_REMATCH[10]}
    uri_path=${BASH_REMATCH[11]}
    uri_query=${BASH_REMATCH[12]}
    uri_fragment=${BASH_REMATCH[13]}

    # path parsing
    count=0
    path="$uri_path"
    pattern='^/+([^/]+)'
    while [[ $path =~ $pattern ]]; do
        eval "uri_parts[$count]=\"${BASH_REMATCH[1]}\""
        path="${path:${#BASH_REMATCH[0]}}"
        let count++
    done

    # query parsing
    count=0
    query="$uri_query"
    pattern='^[?&]+([^= ]+)(=([^&]*))?'
    while [[ $query =~ $pattern ]]; do
        eval "uri_args[$count]=\"${BASH_REMATCH[1]}\""
        eval "uri_arg_${BASH_REMATCH[1]}=\"${BASH_REMATCH[3]}\""
        query="${query:${#BASH_REMATCH[0]}}"
        let count++
    done

    # return success
    return 0
}

function executeRestCall(){
  local method=$1
  local url=$2

  uri_parser $url
  PAYLOAD=$(printf "" | openssl dgst -binary -sha256 | od -An -vtx1 | sed 's/[ \n]//g' | sed 'N;s/\n//')
  CANONICAL_REQUEST="$method\n$uri_path\n\nhost:$uri_address\nx-amz-date:$DATE\n\nhost;x-amz-date\n$PAYLOAD"
  CREDENTIAL_SCOPE="$DATE_ONLY/$REGION/$SERVICE/aws4_request"
  STRING_TO_SIGN="$ALGORITHM\n$DATE\n$CREDENTIAL_SCOPE\n$(printf $CANONICAL_REQUEST | openssl dgst -binary -sha256 | od -An -vtx1 | sed 's/[ \n]//g' | sed 'N;s/\n//')"
  SIGNING_KEY=$(sign $SECRET_KEY $DATE_ONLY $REGION $SERVICE)
  SIGNATURE=$(printf "$STRING_TO_SIGN" | openssl dgst -binary -sha256 -mac HMAC -macopt hexkey:$SIGNING_KEY | xxd -p -c 256)
  AUTHORIZATION_HEADER="$ALGORITHM Credential=$ACCESS_KEY/$CREDENTIAL_SCOPE, SignedHeaders=$SIGNED_HEADERS, Signature=$SIGNATURE"
  curl --request $method --url "$url" \
          -H "authorization: $AUTHORIZATION_HEADER" \
          -H "cache-control: no-cache" \
          -H "content-type: application/json" \
          -H "host: $uri_address" \
          -H "x-amz-date: $DATE" \
          -H "x-amz-content-sha256: $PAYLOAD"
}

function uploadFile(){
  local method=$1
  local url=$2
  local filePath=$3

  contentType="text/markdown"

  uri_parser $url

  FILE_CONTENT=$(cat $filePath)
  PAYLOAD=$(printf "$FILE_CONTENT" | openssl dgst -binary -sha256 | od -An -vtx1 | sed 's/[ \n]//g' | sed 'N;s/\n//')
  CANONICAL_REQUEST="$method\n$uri_path\n\nhost:$uri_address\nx-amz-date:$DATE\n\nhost;x-amz-date\n$PAYLOAD"
  CREDENTIAL_SCOPE="$DATE_ONLY/$REGION/$SERVICE/aws4_request"
  STRING_TO_SIGN="$ALGORITHM\n$DATE\n$CREDENTIAL_SCOPE\n$(printf $CANONICAL_REQUEST | openssl dgst -binary -sha256 | od -An -vtx1 | sed 's/[ \n]//g' | sed 'N;s/\n//')"
  SIGNING_KEY=$(sign $SECRET_KEY $DATE_ONLY $REGION $SERVICE)
  SIGNATURE=$(printf "$STRING_TO_SIGN" | openssl dgst -binary -sha256 -mac HMAC -macopt hexkey:$SIGNING_KEY | xxd -p -c 256)
  AUTHORIZATION_HEADER="$ALGORITHM Credential=$ACCESS_KEY/$CREDENTIAL_SCOPE, SignedHeaders=$SIGNED_HEADERS, Signature=$SIGNATURE"
  curl --request $method --url "$url" \
            -H "authorization: $AUTHORIZATION_HEADER" \
            -H "cache-control: no-cache" \
            -H "content-type: $contentType" \
            -H "host: $uri_address" \
            -H "x-amz-date: $DATE" \
            -H "x-amz-content-sha256: $PAYLOAD" \
            --upload-file $filePath

  echo "file upload finished"
}


responseCreateBucket=$(executeRestCall PUT "${MINIO_SERVER_URL}/$BUCKET")
responseUploadFile=$(uploadFile PUT "$OBJECT_URL" "$FILE_PATH")

echo "#######################"
echo $responseCreateBucket
echo $responseUploadFile
echo "#######################"


