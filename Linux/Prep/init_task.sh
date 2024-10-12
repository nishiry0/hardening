#!/usr/bin/env bash

# オプションの解析
interactive=false
password_file=""
delete_password_file=false  # デフォルトは削除しない
default_password="P@ssw0rd"
backup_dir="./backup"  # デフォルトのバックアップディレクトリ

while getopts ":ip:db:" opt; do
  case $opt in
    i)
      interactive=true
      ;;
    p)
      password_file="$OPTARG"
      ;;
    d)
      if [ -n "$password_file" ];then
        delete_password_file=true  # -d が指定されていて -p も指定されている場合に削除を有効化
      else
        echo "警告: -d オプションが指定されましたが、-p オプションが指定されていません。-d は無視されます。" >&2
        delete_password_file=false
      fi
      ;;
    b)
      backup_dir="$OPTARG"
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
USERLIST_FILE="user_list.txt"
LOG_FILE="script.log"

touch "$LOG_FILE"

# ログ関数
log(){
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# バックアップディレクトリの作成
create_backup_dir(){
    if [ -d "$backup_dir" ];then
        echo "エラー: $backup_dir は既に存在します。" >&2
        log "Error: $backup_dir already exists."
        exit 1
    else
        mkdir -p "$backup_dir"
        if [ $? -eq 0 ];then
            log "Backup directory $backup_dir created."
        else
            echo "エラー: $backup_dir の作成に失敗しました。" >&2
            log "Error: Failed to create backup directory $backup_dir."
            exit 1
        fi
    fi
}

# パスワード取得関数（パスワードファイルがない場合はデフォルトパスワードを使用）
get_password(){
    if [ -n "$password_file" ];then
        if [ -f "$password_file" ];then
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
        echo "$default_password"
    fi
}

# ファイルバックアップ関数
backup_files(){
    cp /etc/passwd /etc/passwd.bak
    cp /etc/shadow /etc/shadow.bak
    log "Backup of /etc/passwd and /etc/shadow created."
}

# システム情報列挙関数（ファイルを分けて保存）
enumerate_func (){
    log "Starting system enumeration."
    create_backup_dir  # バックアップディレクトリの作成

    # 各コマンド結果を個別ファイルに保存
    ps auxf > "$backup_dir/ps_auxf.txt" && log "ps auxf saved to $backup_dir/ps_auxf.txt"
    ip a > "$backup_dir/ip_a.txt" && log "ip a saved to $backup_dir/ip_a.txt"
    ip r > "$backup_dir/ip_r.txt" && log "ip r saved to $backup_dir/ip_r.txt"
    ss -ltpn > "$backup_dir/ss_ltpn.txt" && log "ss -ltpn saved to $backup_dir/ss_ltpn.txt"
    systemctl list-unit-files > "$backup_dir/systemctl_list_unit_files.txt" && log "systemctl list-unit-files saved to $backup_dir/systemctl_list_unit_files.txt"
    iptables -L > "$backup_dir/iptables_L.txt" && log "iptables -L saved to $backup_dir/iptables_L.txt"

    # 追加のシステム情報
    df > "$backup_dir/df.txt" && log "df saved to $backup_dir/df.txt"
    uname -a > "$backup_dir/uname.txt" && log "uname -a saved to $backup_dir/uname.txt"
    lscpu > "$backup_dir/lscpu.txt" && log "lscpu saved to $backup_dir/lscpu.txt"
    lsblk > "$backup_dir/lsblk.txt" && log "lsblk saved to $backup_dir/lsblk.txt"

    if command -v sestatus >/dev/null 2>&1;then
        sestatus > "$backup_dir/sestatus.txt" && log "sestatus saved to $backup_dir/sestatus.txt"
    else
        echo "sestatus command not found." >> "$backup_dir/sestatus.txt" && log "sestatus command not found."
    fi

    if command -v getenforce >/dev/null 2>&1;then
        getenforce > "$backup_dir/getenforce.txt" && log "getenforce saved to $backup_dir/getenforce.txt"
    else
        echo "getenforce command not found." >> "$backup_dir/getenforce.txt" && log "getenforce command not found."
    fi

    cat /etc/passwd > "$backup_dir/passwd.txt" && log "/etc/passwd saved to $backup_dir/passwd.txt"
    cat /etc/group > "$backup_dir/group.txt" && log "/etc/group saved to $backup_dir/group.txt"

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

        read -p "ユーザーのパスワードを変更しますか？ (Y/n): " pw_answer
        if [[ ! "$pw_answer" =~ ^[Nn]$ ]];then
            change_passwords_func
        else
            log "Password change skipped by user."
        fi

        delete_password_file_func
    else
        backup_files
        enumerate_func
        backup_admin_func
        list_users_func
        change_passwords_func
        delete_password_file_func
    fi

    # script.logをバックアップディレクトリにコピー
    cp "$LOG_FILE" "$backup_dir/script.log"
    log "script.log copied to $backup_dir"
}

# メイン関数を呼び出す
main_func
