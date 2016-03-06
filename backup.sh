#!/bin/bash

##
# Backup MySQL
# Author: Matthew Spurrier
# Website: http://www.digitalsparky.com/
##

## START CONFIG
DBUSER=''
DBPASS=''
DBHOST='127.0.0.1'
BACKUPPATH='/opt/mysql-backup'
KEEPFOR=7

## END CONFIG

CMD=${1-"--help"}
MYSQLBIN="$(which mysql)"
MYSQLDUMPBIN="$(which mysqldump)"
MYSQL="${MYSQLBIN} -p${DBPASS} -u${DBUSER} -h ${DBHOST}"
MYSQLDUMP="${MYSQLDUMPBIN} -p${DBPASS} -u${DBUSER} -h ${DBHOST} --skip-lock-tables --single-transaction --flush-logs --master-data=2 --skip-extended-insert --order-by-primary"
HOSTNAME="$(hostname)"
CULLKEEPFOR=${KEEPFOR-"30"}
PID=$$

## Dependency Checks
# MYSQLDUMP
if [ ! -x "${MYSQLDUMPBIN}" ]; then
    echo "mysqlump is missing or non-executable and is required for this to run, this package is provided by mysql-client, please resolve this."
    exit 1
fi
# MYSQL
if [ ! -x "${MYSQLBIN}" ]; then
    echo "mysql is missing or non-executable and is required for this to run, this package is provided by mysql-client, please resolve this."
    exit 1
fi

printHelp () {
    cat <<EOF
MySQL Backup Script
Usage: $0 [--help|--clean|--backup|--restore]

--clean: Run's backup cull/cleanup job
--backup [database]: Runs backup job (leave 'database' variable to run all)
--restore [restorefile] [newdatabase]: Restore's an archive to the new database name

EOF
    exit 1
}

msg () {
    TIME=$(date +"%D %T")
    case $2 in
        0)
            echo -ne "[ ${TIME} ] $1\r"
            ;;
        1)
            echo -e "\t\t\t\t\t\t\t\t\t\t [ $1 ]"
            ;;
        *)
            echo "[ ${TIME} ] $1"
            ;;
    esac

}

backupDB () {
    DATE=$(date +%Y%m%d)
    HOUR=$(date +%H)
    HOURBACKUP="${BACKUPPATH}/${DBNAME}/${DATE}/${HOUR}.dump"
    msg "Beginning backup of ${DBNAME}"
    if [ ! -d "${BACKUPPATH}/${DBNAME}/${DATE}" ]; then
        mkdir -p "${BACKUPPATH}/${DBNAME}/${DATE}"
        if [ "$?" -ne 0 ]; then
            echo "Failed to create backup path" >&2
            exit 1
        fi
    fi
    msg "Creating hourly backup for ${DATE} at ${HOUR}" 0
    if [ -f "${HOURBACKUP}" ]; then
        msg "FAILED" 1
        echo "This hours backup has already been run, exiting." >&2
        exit 1
    fi
    PIDFILE="${BACKUPPATH}/${DBNAME}-${DATE}-${HOUR}.pid"
    if [ ! -f "${PIDFILE}" ]; then
        echo "${PID}" > "${PIDFILE}"
    else
        CHECKPID=$(cat "${PIDFILE}" 2>/dev/null 3>/dev/null)
        if [ $(ps -p "${CHECKPID}" > /dev/null 2>&1 3>&1; echo $?) -eq 0 ]; then
            msg "FAILED" 1
            echo "This hours backup has already been run, and is still running, exiting." >&2
            exit 1
        fi
    fi
    chown -R mysql:mysql "${BACKUPPATH}"
    ${MYSQLDUMP} "${DBNAME}" | gzip > "${HOURBACKUP}" 2>/dev/null
    if [ "$?" -ne 0 ]; then
        msg "FAILED" 1
        echo "Failed to create backup of ${DBNAME}" >&2
        rm "${PIDFILE}"
        exit 1
    fi
    msg "OK" 1
    rm "${PIDFILE}"
    msg "Backup of ${DBNAME} completed successfully"
}

cleanup () {
    for FILE in $(find "${BACKUPPATH}" -maxdepth 2 -mindepth 2 -type d -mtime +"${CULLKEEPFOR}" -print); do
        rm -rf "${FILE}"
    done
}

restoreDB () {
    msg "Restoring ${RESTOREFILE} to ${DBNAME}" 0
    cat "${RESTOREFILE}" | gzip -dc | ${MYSQL} "${DBNAME}"
    if [ "$?" -ne 0 ]; then
        msg "FAILED" 1
        echo "Failed to restore ${RESTOREFILE} to ${DBNAME}" >&2
        exit 1
    fi
    msg "OK" 1
    msg "Restore of ${RESTOREFILE} to ${DBNAME} completed successfully"
}

case "${CMD}" in
    "--help")
        printHelp
        ;;
    "--clean")
        cleanup
        ;;
    "--restore")
        if [ -n "$2" ]; then
            if [ ! -f "$2" ]; then
                echo "Please specify restore file path"
                exit 1
            fi
            RESTOREFILE="$2"
        else
            echo "Please specify restore file path"
            exit 1
        fi
        DBLIST=$(${MYSQL} -N -B -e 'show databases' | grep -v -E 'mysql|performance_schema|test|information_schema')
        if [ -n "$3" ]; then
            echo "${DBLIST}" | grep "$3" > /dev/null 2>&1
            if [ "$?" -ne 0 ]; then
                echo "Specificied database '$3' does not exist" >&2
                exit 1
            else
                DBNAME="$3"
            fi
            exit 1
        else
            echo "Please specify destination db"
            exit 1
        fi
        restoreDB
        ;;
    "--backup")
        DBLIST=$(${MYSQL} -N -B -e 'show databases' | grep -v -E 'mysql|performance_schema|test|information_schema')
        if [ "$?" -ne 0 ]; then
            echo "Unable to get database list, this means backups can't run!!" >&2
            exit 1
        fi
        if [ -n "$2" ]; then    
            echo "${DBLIST}" | grep "$2" > /dev/null 2>&1
            if [ "$?" -ne 0 ]; then
                echo "Specificied database '$2' does not exist" >&2
                exit 1
            else
                DBNAME="$2"
                backupDB
            fi
        else
            for DBNAME in ${DBLIST}; do
                $0 --backup "${DBNAME}"
            done
        fi
        ;;
    *)
        printHelp
        ;;
esac
