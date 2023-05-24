#!/bin/bash

if [[ -z ${BUCKET_NAME} || -z ${GIT_EMAIL} || -z ${GIT_NAME} ]]; then
    echo "The destination bucket name (BUCKET_NAME), git email (GIT_EMAIL), and git user name (GIT_NAME) are required as environment variables."
else
  REPO="tar1090-db"
  PKG_MANAGER=$(command -v yum || command -v apt || command -v dnf)
  echo "Using package manager: ${PKG_MANAGER}"
  git config user.email "${GIT_EMAIL}"
  git config user.name "${GIT_NAME}"

  # archive old tar1090-db
  aws s3 mv "s3://${BUCKET_NAME}/${REPO}/latest" "s3://${BUCKET_NAME}/${REPO}/$(date +%F-%H-%M-%S-%N)" --recursive

  # install packages required for update script
  ${PKG_MANAGER} install -y wget
  ${PKG_MANAGER} install -y p7zip
  ./update.sh

  # push updated db folder to S3
  aws s3 cp db "s3://${BUCKET_NAME}/${REPO}/latest/db" --recursive

  # generate updated csv on csv branch of tar1090-db
  git reset --hard HEAD
  ./csv.sh
  git reset --hard HEAD

  # switch to branch to get latest file
  git checkout csv
  aws s3 cp ./aircraft.csv.gz "s3://${BUCKET_NAME}/${REPO}/latest/aircraft.csv.gz"
  git checkout master
fi