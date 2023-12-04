#!/bin/bash

# Конфигурация сервера 1 (source)
server1_user="user1"
server1_host="server1.example.com"
server1_password="password1"

# Конфигурация сервера 2 (destination)
server2_user="user2"
server2_host="server2.example.com"
server2_password="password2"

source_path="/path/on/server1/"
destination_path="/path/on/server2/"

log_file="/var/log/rsync_transfer.log"

max_retries=100
attempt=0
fixed_backoff_time=10 # время ожидания между попытками в секундах
slack_webhook_url="SLACK_WEBHOOK_URL"

function check_hash_before {
    local path=$1
    local user=$2
    local host=$3
    local password=$4

    echo "$(sshpass -p $password ssh -o StrictHostKeyChecking=no $user@$host "md5sum $path" | awk '{ print $1 }')"
}

function check_hash_after {
    local path=$1
    local user=$2
    local host=$3
    local password=$4

    echo "$(sshpass -p $password ssh -o StrictHostKeyChecking=no $user@$host "md5sum $path" | awk '{ print $1 }')"
}



# Функция отправки уведомления в Slack
function send_slack_notification {
    message=$1
    curl -X POST -H 'Content-type: application/json' --data "{\"text\":\"$message\"}" $slack_webhook_url
}

while [ $attempt -lt $max_retries ]
do
    hash_before=$(check_hash_before "$source_path" $server1_user $server1_host $server1_password)

    # Использование sshpass для автоматического ввода пароля...
    # [команда rsync]

    if [ "$?" = "0" ] ; then
        hash_after=$(check_hash_after "$destination_path" $server2_user $server2_host $server2_password)

        if [ "$hash_before" == "$hash_after" ]; then
            echo "$(date) - rsync completed normally, hash match" >> $log_file
            send_slack_notification "rsync from $server1_host to $server2_host completed successfully, hash match"
            exit
        else
            echo "$(date) - Hash mismatch error after rsync" >> $log_file
            send_slack_notification "Hash mismatch error after rsync from $server1_host to $server2_host"
            exit 1
        fi
    else
        echo "$(date) - Rsync failure. Attempt $((attempt+1)) of $max_retries. Retrying in $fixed_backoff_time seconds..." >> $log_file
        attempt=$((attempt+1))
        sleep $fixed_backoff_time
    fi
done

error_message="$(date) - Failed to rsync after $max_retries attempts from $server1_host to $server2_host."
echo $error_message >> $log_file
send_slack_notification $error_message
