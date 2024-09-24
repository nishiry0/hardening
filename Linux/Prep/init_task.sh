#!/usr/bin/env bash

# オプションの解析
interactive=false
while getopts ":i" opt; do
  case $opt in
    i)
      interactive=true
      ;;
    \?)
      echo "無効なオプションです: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# スクリプトがroot権限で実行されているか確認
if [ "$EUID" -ne 0 ]; then
    echo "このスクリプトはroot権限で実行する必要があります。" >&2
    exit 1
fi

# 出力ファイルとログファイルの設定と権限
SYSINFO_FILE="sysinfo.txt"
USERLIST_FILE="user_list.txt"
LOG_FILE="script.log"

touch "$SYSINFO_FILE" "$LOG_FILE"
chmod 600 "$SYSINFO_FILE" "$LOG_FILE"

# ログ関数
log(){
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# ファイルバックアップ関数
backup_files(){
    cp /etc/passwd /etc/passwd.bak
    cp /etc/shadow /etc/shadow.bak
    log "Backup of /etc/passwd and /etc/shadow created."
}

check_crontab_func (){
    for user in $(cut -f1 -d: /etc/passwd); do
        echo "###### $user crontab is:" >> "$SYSINFO_FILE"
        cat /var/spool/cron/{crontabs/$user,$user} 2>/dev/null >> "$SYSINFO_FILE"
    done
}

enumerate_func (){
    log "Starting system enumeration."
    date -u >> "$SYSINFO_FILE"
    uname -a >> "$SYSINFO_FILE"

    if . /etc/os-release ; then
        OS=$NAME
    else
        . /usr/lib/os-release
        OS=$NAME
    fi

    echo "OS is $ID" >> "$SYSINFO_FILE"
    lscpu >> "$SYSINFO_FILE"
    lsblk >> "$SYSINFO_FILE"
    ip a >> "$SYSINFO_FILE"

    # netstat または ss の使用
    if command -v netstat >/dev/null 2>&1; then
        netstat -auntp >> "$SYSINFO_FILE"
    elif command -v ss >/dev/null 2>&1; then
        ss -auntp >> "$SYSINFO_FILE"
    else
        echo "Neither netstat nor ss command found." >> "$SYSINFO_FILE"
    fi

    df >> "$SYSINFO_FILE"
    ls -latr /var/acc >> "$SYSINFO_FILE"

    # ls コマンドの出力
    ls -latr /var/log/* >> "$SYSINFO_FILE"
    ls -la /etc/syslog >> "$SYSINFO_FILE"

    check_crontab_func
    cat /etc/crontab >> "$SYSINFO_FILE"
    ls -la /etc/cron.* >> "$SYSINFO_FILE"

    # SELinux のステータス確認
    if command -v sestatus >/dev/null 2>&1; then
        sestatus >> "$SYSINFO_FILE"
    else
        echo "sestatus command not found." >> "$SYSINFO_FILE"
    fi

    if command -v getenforce >/dev/null 2>&1; then
        getenforce >> "$SYSINFO_FILE"
    else
        echo "getenforce command not found." >> "$SYSINFO_FILE"
    fi

    # Bash 履歴の取得
    if [ -f /root/.bash_history ]; then
        cat /root/.bash_history >> "$SYSINFO_FILE"
    fi

    if [ -f ~/.bash_history ]; then
        cat ~/.bash_history >> "$SYSINFO_FILE"
    fi

    cat /etc/group >> "$SYSINFO_FILE"
    cat /etc/passwd >> "$SYSINFO_FILE"

    # UFW のステータス確認
    if [ "$OS" = "Ubuntu" ] || [ "$OS" = "Debian" ]; then
        if command -v ufw >/dev/null 2>&1; then
            ufw_status=$(ufw status)
            echo "ufw $ufw_status" >> "$SYSINFO_FILE"
        else
            echo "ufw command not found." >> "$SYSINFO_FILE"
        fi
    fi
    log "System enumeration completed."
}

backup_admin_func (){
    log "Starting backup admin user creation."

    adduser --disabled-password --gecos "" bkadmin
    if [ $? -ne 0 ]; then
        log "User bkadmin already exists."
    else
        log "User bkadmin created successfully."
    fi

    adduser --disabled-password --gecos "" bkadmin2
    if [ $? -ne 0 ]; then
        log "User bkadmin2 already exists."
    else
        log "User bkadmin2 created successfully."
    fi

    usermod -aG sudo bkadmin
    if [ $? -ne 0 ]; then
        log "Failed to add bkadmin to sudo group."
    else
        log "User bkadmin added to sudo group."
    fi

    usermod -aG sudo bkadmin2
    if [ $? -ne 0 ]; then
        log "Failed to add bkadmin2 to sudo group."
    else
        log "User bkadmin2 added to sudo group."
    fi

    log "Backup admin user creation completed."
}

list_users_func (){
    log "Listing users with UID >= 1000 and UID != 65534."
    # UIDが1000以上かつUIDが65534でないユーザーのみを抽出（システムユーザーとnobodyを除外）
    awk -F: '($3 >= 1000) && ($3 != 65534)' /etc/passwd | cut -d: -f1 > "$USERLIST_FILE"
    log "User list created in $USERLIST_FILE."
}

change_passwords_func (){
    log "Starting password changes for listed users."

    # パスワード変更の対象外とするユーザーをリストに追加
    EXCLUDED_USERS=("hardening") # ここに除外したいユーザー名を追加

    for user in $(cat "$USERLIST_FILE"); do
        if [[ " ${EXCLUDED_USERS[@]} " =~ " $user " ]]; then
            log "Skipping password change for $user."
            continue
        fi

        # 固定パスワードを設定
        PASS=P@ssw0rd

        echo "Changing password for $user"
        echo "$user,$PASS" >> "passwords_changed.txt"
        echo -e "$PASS\n$PASS" | passwd "$user"

        if [ $? -eq 0 ]; then
            log "Password changed successfully for $user."
        else
            log "Failed to change password for $user."
        fi
    done
    log "Password changes completed."
}

main_func (){
    if [ "$interactive" = true ]; then
        read -p "システム情報の収集を行いますか？ (Y/n): " answer
        if [[ ! "$answer" =~ ^[Nn]$ ]]; then
            enumerate_func
        else
            log "System enumeration skipped by user."
        fi

        read -p "バックアップ管理者ユーザーを作成しますか？ (Y/n): " answer
        if [[ ! "$answer" =~ ^[Nn]$ ]]; then
            backup_admin_func
        else
            log "Backup admin user creation skipped by user."
        fi

        read -p "通常ユーザーのリストを作成しますか？ (Y/n): " answer
        if [[ ! "$answer" =~ ^[Nn]$ ]]; then
            list_users_func
        else
            if [ -f "$USERLIST_FILE" ]; then
                echo "$USERLIST_FILE が既に存在します。次回実行時にはこのファイルが使用されます。"
                log "User list creation skipped by user; existing $USERLIST_FILE will be used in next run."
            else
                echo "$USERLIST_FILE が存在しません。パスワード変更を行うにはユーザーリストが必要です。"
                log "User list creation skipped and $USERLIST_FILE does not exist. Cannot proceed with password changes."
                exit 1
            fi
        fi

        # パスワードを変更するユーザーのリストを作成
        EXCLUDED_USERS=("hardening") # ここに除外したいユーザー名を追加
        PASSWORD_USERS=()
        for user in $(cat "$USERLIST_FILE"); do
            if [[ ! " ${EXCLUDED_USERS[@]} " =~ " $user " ]]; then
                PASSWORD_USERS+=("$user")
            fi
        done

        # パスワード変更対象ユーザーのリストを表示
        if [ ${#PASSWORD_USERS[@]} -eq 0 ]; then
            echo "パスワードを変更するユーザーがいません。"
            log "No users to change password for."
        else
            echo "以下のユーザーのパスワードを変更します（除外ユーザーを除く）:"
            printf '%s\n' "${PASSWORD_USERS[@]}"
            read -p "これらのユーザーのパスワードを変更してよろしいですか？ (Y/n): " pw_answer
            if [[ ! "$pw_answer" =~ ^[Nn]$ ]]; then
                backup_files
                change_passwords_func
            else
                log "Password changes skipped by user."
                echo "次回実行時、既存のユーザーリストが使用されます。"
            fi
        fi
    else
        backup_files
        enumerate_func
        backup_admin_func
        list_users_func
        change_passwords_func
    fi
}

main_func
