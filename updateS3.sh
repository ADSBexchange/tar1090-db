#!/bin/bash

if [[ -z ${BUCKET_NAME} ]]; then
    echo "The bucket name of the destination for database updates is required as an environment variable."
else
  REPO="tar1090-db"

  # archive old tar1090-db
  aws s3 mv "s3://${BUCKET_NAME}/${REPO}/latest" "s3://${BUCKET_NAME}/${REPO}/$(date +%F-%H-%M-%S-%N)"

  # install packages required for update script
  yum install -y wget
  yum install -y p7zip
  ./update.sh

  # push updated db folder to S3
  aws s3 cp db "s3://${BUCKET_NAME}/${REPO}/latest/db"

  # generate updated csv on csv branch of tar1090-db
  ./csv.sh

  # switch to branch to get latest file
  git checkout csv
  aws s3 cp ./aircraft.csv.gz "s3://${BUCKET_NAME}/${REPO}/latest/aircraft.csv.gz"
  git checkout master
fi