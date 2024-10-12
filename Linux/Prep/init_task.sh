#!/usr/bin/env bash

# オプションの解析
interactive=false
password_file=""
delete_password_file=false  # デフォルトは削除しない
default_password="P@ssw0rd"

while getopts ":ip:d" opt; do
  case $opt in
    i)
      interactive=true
      ;;
    p)
      password_file="$OPTARG"
      ;;
    d)
      if [ -n "$password_file" ]; then
        delete_password_file=true  # -d が指定されていて -p も指定されている場合に削除を有効化
      else
        echo "警告: -d オプションが指定されましたが、-p オプションが指定されていません。-d は無視されます。" >&2
        delete_password_file=false
      fi
      ;;
    \?)
      echo "無効なオプションです: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# スクリプトがroot権限で実行されているか確認
if [ "$EUID" -ne 0 ];then
    echo "このスクリプトはroot権限で実行する必要があります。" >&2
    exit 1
fi

# 出力ファイルとログファイルの設定
SYSINFO_FILE="sysinfo.txt"
USERLIST_FILE="user_list.txt"
LOG_FILE="script.log"

touch "$SYSINFO_FILE" "$LOG_FILE"

# ログ関数
log(){
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# パスワード取得関数（パスワードファイルがない場合はデフォルトパスワードを使用）
get_password(){
    if [ -n "$password_file" ];then
        # パスワードファイルが指定された場合
        if [ -f "$password_file" ];then
            # ファイルに1行のみが含まれているか確認
            PASSWORD=$(cat "$password_file")
            if [ $(wc -l < "$password_file") -ne 1 ];then
                echo "エラー: $password_file は1行のみ含む必要があります。" >&2
                log "Error: $password_file contains more than one line."
                exit 1
            fi
            echo "$PASSWORD"
        else
            echo "エラー: 指定されたパスワードファイルが存在しません: $password_file" >&2
            log "Error: Specified password file not found: $password_file"
            exit 1
        fi
    else
        # -pが指定されていない場合はデフォルトのパスワードを使用
        echo "$default_password"
    fi
}

# ファイルバックアップ関数
backup_files(){
    cp /etc/passwd /etc/passwd.bak
    cp /etc/shadow /etc/shadow.bak
    log "Backup of /etc/passwd and /etc/shadow created."
}

# crontabのチェック関数
check_crontab_func (){
    for user in $(cut -f1 -d: /etc/passwd);do
        echo "###### $user crontab is:" >> "$SYSINFO_FILE"
        cat /var/spool/cron/{crontabs/$user,$user} 2>/dev/null >> "$SYSINFO_FILE"
    done
}

# システム情報列挙関数
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

    if command -v netstat >/dev/null 2>&1;then
        netstat -auntp >> "$SYSINFO_FILE"
    elif command -v ss >/dev/null 2>&1;then
        ss -auntp >> "$SYSINFO_FILE"
    else
        echo "Neither netstat nor ss command found." >> "$SYSINFO_FILE"
    fi

    df >> "$SYSINFO_FILE"
    check_crontab_func
    cat /etc/crontab >> "$SYSINFO_FILE"
    ls -la /etc/cron.* >> "$SYSINFO_FILE"

    if command -v sestatus >/dev/null 2>&1;then
        sestatus >> "$SYSINFO_FILE"
    else
        echo "sestatus command not found." >> "$SYSINFO_FILE"
    fi

    if command -v getenforce >/dev/null 2>&1;then
        getenforce >> "$SYSINFO_FILE"
    else
        echo "getenforce command not found." >> "$SYSINFO_FILE"
    fi

    if [ -f /root/.bash_history ];then
        cat /root/.bash_history >> "$SYSINFO_FILE"
    fi

    if [ -f ~/.bash_history ];then
        cat ~/.bash_history >> "$SYSINFO_FILE"
    fi

    cat /etc/group >> "$SYSINFO_FILE"
    cat /etc/passwd >> "$SYSINFO_FILE"

    if [ "$OS" = "Ubuntu" ] || [ "$OS" = "Debian" ];then
        if command -v ufw >/dev/null 2>&1;then
            ufw_status=$(ufw status)
            echo "ufw $ufw_status" >> "$SYSINFO_FILE"
        else
            echo "ufw command not found." >> "$SYSINFO_FILE"
        fi
    fi
    log "System enumeration completed."
}

# バックアップ管理者ユーザー作成関数
backup_admin_func (){
    log "Starting backup admin user creation."

    adduser --disabled-password --gecos "" bkadmin
    if [ $? -ne 0 ];then
        log "User bkadmin already exists."
    else
        log "User bkadmin created successfully."
    fi

    adduser --disabled-password --gecos "" bkadmin2
    if [ $? -ne 0 ];then
        log "User bkadmin2 already exists."
    else
        log "User bkadmin2 created successfully."
    fi

    usermod -aG sudo bkadmin
    if [ $? -ne 0 ];then
        log "Failed to add bkadmin to sudo group."
    else
        log "User bkadmin added to sudo group."
    fi

    usermod -aG sudo bkadmin2
    if [ $? -ne 0 ];then
        log "Failed to add bkadmin2 to sudo group."
    else
        log "User bkadmin2 added to sudo group."
    fi

    log "Backup admin user creation completed."
}

# ユーザーリスト作成関数
list_users_func (){
    log "Listing users with UID >= 1000 and UID != 65534."
    awk -F: '($3 >= 1000) && ($3 != 65534)' /etc/passwd | cut -d: -f1 > "$USERLIST_FILE"
    log "User list created in $USERLIST_FILE."
}

# パスワード変更関数
change_passwords_func (){
    log "Starting password changes for listed users."

    EXCLUDED_USERS=("hardening")

    PASS=$(get_password)  # 正しいパスワードを取得

    for user in $(cat "$USERLIST_FILE");do
        if [[ " ${EXCLUDED_USERS[@]} " =~ " $user " ]];then
            log "Skipping password change for $user."
            continue
        fi

        echo "Changing password for $user"
        echo "$user,$PASS" >> "passwords_changed.txt"
        echo -e "$PASS\n$PASS" | passwd "$user"

        if [ $? -eq 0 ];then
            log "Password changed successfully for $user."
        else
            log "Failed to change password for $user."
        fi
    done
    log "Password changes completed."
}

# スクリプト完了後にパスワードファイルを削除する関数
delete_password_file_func(){
    if [ "$delete_password_file" = true ] && [ -n "$password_file" ];then
        if [ -f "$password_file" ];then
            rm "$password_file"
            log "Password file $password_file deleted."
            echo "Password file $password_file deleted."  # 削除したことを出力
        fi
    fi
}

# メイン処理関数
main_func (){
    if [ "$interactive" = true ];then
        read -p "システム情報の収集を行いますか？ (Y/n): " answer
        if [[ ! "$answer" =~ ^[Nn]$ ]];then
            enumerate_func
        else
            log "System enumeration skipped by user."
        fi

        read -p "バックアップ管理者ユーザーを作成しますか？ (Y/n): " answer
        if [[ ! "$answer" =~ ^[Nn]$ ]];then
            backup_admin_func
        else
            log "Backup admin user creation skipped by user."
        fi

        read -p "通常ユーザーのリストを作成しますか？ (Y/n): " answer
        if [[ ! "$answer" =~ ^[Nn]$ ]];then
            list_users_func
        else
            if [ -f "$USERLIST_FILE" ];then
                echo "$USERLIST_FILE が既に存在します。このファイルが使用されます。"
                log "User list creation skipped by user; existing $USERLIST_FILE will be used."
            else
                echo "$USERLIST_FILE が存在しません。パスワード変更を行うには $USERLIST_FILE が必要です。"
                log "User list creation skipped and $USERLIST_FILE does not exist. Cannot proceed with password changes."
                exit 1
            fi
        fi

        # パスワード変更処理
        read -p "ユーザーのパスワードを変更しますか？ (Y/n): " pw_answer
        if [[ ! "$pw_answer" =~ ^[Nn]$ ]];then
            change_passwords_func
        else
            log "Password change skipped by user."
        fi

        # 最後にパスワードファイル削除関数を呼び出し
        delete_password_file_func
    else
        backup_files
        enumerate_func
        backup_admin_func
        list_users_func
        change_passwords_func
        delete_password_file_func
    fi
}

# メイン関数を呼び出す
main_func

