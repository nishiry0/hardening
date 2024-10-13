#!/bin/bash

# インタラクティブモード: "sudo ssh_harden.sh i"
# クイックモード: "sudo ssh_harden.sh q"

# 管理者権限で実行されているか確認する関数
function check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "このスクリプトを実行するには管理者権限が必要です。" 1>&2
    exit 1
  fi
}

# SSHD_CONF_LOC の初期値を設定
SSHD_CONF_LOC="/etc/ssh/sshd_config"

# sshd_config が適切な場所にあるか確認する関数
function sshd_config_check() {	 
  if [[ -f $SSHD_CONF_LOC ]]; then
    echo "sshd_config が見つかりました"
  else
    echo -n "sshd_config が見つかりません。パスを指定してください: "
    read SSHD_CONF_LOC
    sshd_config_check
  fi
}

# sshd_config のバックアップを作成する関数
function backup_sshd_config() {
  cp $SSHD_CONF_LOC .
  echo "sshd_config を $(pwd) にバックアップしました"
}

# SSHプロトコルを変更する関数
function change_protocol() {
  sed -i -e 's/^.*Protocol.*$/Protocol 2/' $SSHD_CONF_LOC
}

# root ログインの許可設定を変更する関数
function root_login() {
  sed -i -e 's/^.*PermitRootLogin.*$/PermitRootLogin no/' $SSHD_CONF_LOC
}

# SSHポートを変更する関数
function ssh_port() {
  echo -n "希望するポート番号を入力してください (1-65535): "
  read port_number
  if [ $port_number -gt 0 -a $port_number -lt 65536  ] ; then
    sed -i -e "s/^.*Port.*$/Port $port_number/" $SSHD_CONF_LOC
  else 
    echo "1 から 65535 の間のポート番号を指定してください。"
    ssh_port
  fi  
}

# 最大認証試行回数を変更する関数
function max_auth() {
  echo -n "許可する最大認証試行回数を入力してください (1-10): "
  read auth_attempts
  if [ $auth_attempts -gt 0 -a $auth_attempts -lt 11  ] ; then
    sed -i -e "s/^.*MaxAuthTries.*$/MaxAuthTries $auth_attempts/" $SSHD_CONF_LOC
  else 
    echo "1 から 10 の間で指定してください。"
    max_auth
  fi  
}

# 空のパスワードを無効化する関数
function empty_passwords() {
  sed -i -e 's/^.*PermitEmptyPasswords.*$/PermitEmptyPasswords no/' $SSHD_CONF_LOC
}

# ログインの猶予時間を変更する関数
function login_gt() {
  echo -n "希望する猶予時間を秒単位で入力してください (5-120): "
  read grace_time
  if [ $grace_time -gt 4 -a $grace_time -lt 121  ] ; then
    sed -i -e "s/^.*LoginGraceTime.*$/LoginGraceTime $grace_time/" $SSHD_CONF_LOC
  else
    echo "5 から 120 の間の猶予時間を指定してください。"
    login_gt
  fi
}

# パスワード認証を無効化する関数
function disable_pw() {
  sed -i -e 's/^.*PasswordAuthenticat.*$/PasswordAuthentication no/g' $SSHD_CONF_LOC
}

# rhosts 認証を無効化する関数
function disable_rhosts() {
  sed -i -e 's/^.*IgnoreRhosts.*$/IgnoreRhosts yes/' $SSHD_CONF_LOC
}

# 警告バナーを設定する関数
function warning_banner() {
  touch /etc/ssh/sshd_banner
  cat >/etc/ssh/sshd_banner <<EOF
   WARNING : Unauthorized access to this system is forbidden and will be
   prosecuted by law. By accessing this system, you agree that your actions
   may be monitored if unauthorized usage is suspected.
EOF
vi /etc/ssh/sshd_banner
sed -i -e 's=^.*Banner.*$=Banner /etc/ssh/sshd_banner=' $SSHD_CONF_LOC
}

# SELinux の設定を更新する関数（SSHポート番号に対応させる）
function selinux_update() {	
  if [[ -z "$(swapon -s)" ]] ; then
    echo "スワップスペースが有効ではありません。64MB の一時的なスワップファイルを作成します。"
    echo "(SELinux を変更するために必要です)"
    dd if=/dev/zero of=/temp_swapfile1 bs=1024 count=64000
    chown root:root /temp_swapfile1
    chmod 600 /temp_swapfile1
    mkswap /temp_swapfile1
    swapon /temp_swapfile1
  fi
  
  echo "SELinux に新しいポート番号を設定します。"
  echo "ポート番号: $port_number"
  semanage port -a -t ssh_port_t -p tcp $port_number
  
  if [[ -f /temp_swapfile1 ]] ; then
    echo "一時的なスワップファイルを削除します。"
    swapoff /temp_swapfile1
    rm /temp_swapfile1
  fi
}

# SELinux が Enforcing モードか Permissive モードか確認する関数
function selinux_check() {
  if [[ "$(getenforce)" == "Enforcing" ]] ; then
    echo "SELinux は Enforcing モードで動作しています。"
    echo "ポート番号を変更した場合、SELinux の設定を更新する必要があります。"
    echo -n "SELinux を更新しますか？ (y/n) "
    read selinux_update_response
    case $selinux_update_response in
      [Yy]|[Yy][Ee][Ss]) selinux_update ;;
      [Nn]|[Nn][Oo]) echo "SELinux は変更されません。" ;;
      *) echo "不明なコマンドです..." ;;
    esac 
  fi

 if [[ "$(getenforce)" == "Permissive" ]] ; then
    echo "SELinux は Permissive モードで動作しています。"
    echo "ポート番号を変更した場合、SELinux の設定を更新する必要があります。"
    echo -n "SELinux を更新しますか？ (y/n) "
    read selinux_update_response
    case $selinux_update_response in
      [Yy]|[Yy][Ee][Ss]) selinux_update ;;
      [Nn]|[Nn][Oo]) echo "SELinux は変更されません。" ;;
      *) echo "不明なコマンドです..." ;;
    esac
  fi
}

# FirewallD の設定を更新する関数
function firewalld_update() {
  if [[ "$(firewall-cmd --state)" =~ ^.*not.*$ ]] ; then
    systemctl start firewalld.service 
  fi
  firewall-cmd --permanent --zone=public --add-port=$port_number/tcp
  firewall-cmd --reload
}

# FirewallD がインストールされているか、動作しているか確認する関数
function firewalld_check() {
  if [[ "$(firewall-cmd --state)" == "running" ]] ; then
    echo "FirewallD はこのシステムで動作しています。"
    echo "ポート番号を変更した場合、FirewallD の設定を更新する必要があります。"
    echo -n "FirewallD を更新しますか？ (y/n) "
    read firewalld_update_response
    case $firewalld_update_response in
      [Yy]|[Yy][Ee][Ss]) firewalld_update ;;
      [Nn]|[Nn][Oo]) echo "FirewallD は変更されません。" ;;
      *) echo "不明なコマンドです..." ;;
    esac 
  fi
  
  if [[ "$(firewall-cmd --state)" =~ ^.*not.*$ ]] ; then
    echo "FirewallD はインストールされていますが、動作していません。"
    echo "ポート番号を変更した場合、FirewallD の設定を更新する必要があります。"
    echo -n "FirewallD を有効にして更新しますか？ (y/n) "
    read firewalld_update_response
    case $firewalld_update_response in
      [Yy]|[Yy][Ee][Ss]) firewalld_update ;;
      [Nn]|[Nn][Oo]) echo "FirewallD は変更されません。" ;;
      *) echo "不明なコマンドです..." ;;
    esac 
  fi  
}

# 上記の関数をインタラクティブに実行する関数
function guided_config() {
  check_root
  sshd_config_check	
	
  echo -n "sshd_config をバックアップしますか？ (y/n) "
  read backup_response
  case $backup_response in
    [Yy]|[Yy][Ee][Ss]) backup_sshd_config ;;
    [Nn]|[Nn][Oo]) echo "バックアップは作成されませんでした" ;;
    *) echo "不明なコマンドです..." ;;
  esac

  echo -n "推奨設定: プロトコル2のみにしますか？ (y/n) "
  read protocol_response
  case $protocol_response in
    [Yy]|[Yy][Ee][Ss]) change_protocol ;;
    [Nn]|[Nn][Oo]) echo "プロトコルは変更されませんでした" ;;
    *) echo "不明なコマンドです..." ;;
  esac

  echo -n "推奨設定: root ログインを無効にしますか？ (y/n) "
  read root_login_response
  case $root_login_response in
    [Yy]|[Yy][Ee][Ss]) root_login ;;
    [Nn]|[Nn][Oo]) echo "PermitRootLogin は変更されませんでした" ;;
    *) echo "不明なコマンドです..." ;;
  esac

  echo -n "推奨設定: SSHポートを変更しますか？ (y/n) "
  read ssh_port_response
  case $ssh_port_response in
    [Yy]|[Yy][Ee][Ss]) ssh_port ;;
    [Nn]|[Nn][Oo]) echo "ポートは変更されませんでした" ;;
    *) echo "不明なコマンドです..." ;;
  esac

  echo -n "推奨設定: 最大認証試行回数を変更しますか？ (y/n) "
  read authtries_response
  case $authtries_response in
    [Yy]|[Yy][Ee][Ss]) max_auth ;;
    [Nn]|[Nn][Oo]) echo "最大認証試行回数は変更されませんでした" ;;
    *) echo "不明なコマンドです..." ;;
  esac

  echo -n "推奨設定: 空のパスワードを無効にしますか？ (y/n) "
  read empty_pw_response
  case $empty_pw_response in
    [Yy]|[Yy][Ee][Ss]) empty_passwords ;;
    [Nn]|[Nn][Oo]) echo "PermitEmptyPasswords は変更されませんでした" ;;
    *) echo "不明なコマンドです..." ;;
  esac

  echo -n "推奨設定: ログイン猶予時間を短縮しますか？ (y/n) "
  read login_gt_response
  case $login_gt_response in
    [Yy]|[Yy][Ee][Ss]) login_gt ;;
    [Nn]|[Nn][Oo]) echo "LoginGraceTime は変更されませんでした" ;;
    *) echo "不明なコマンドです..." ;;
  esac

  echo -n "推奨設定: SSH鍵ペアを使用してパスワード認証を無効にしますか？ (y/n) "
  read disable_pw_response
  case $disable_pw_response in
    [Yy]|[Yy][Ee][Ss]) disable_pw ;;
    [Nn]|[Nn][Oo]) echo "PasswordAuthentication は変更されませんでした" ;;
    *) echo "不明なコマンドです..." ;;
  esac

  echo -n "推奨設定: Rhosts を無視しますか？ (y/n) "
  read disable_rhosts_response
  case $disable_rhosts_response in
    [Yy]|[Yy][Ee][Ss]) disable_rhosts ;;
    [Nn]|[Nn][Oo]) echo "IgnoreRhosts は変更されませんでした" ;;
    *) echo "不明なコマンドです..." ;;
  esac

  echo -n "推奨設定: 警告バナーを設定しますか？ (y/n) "
  read warning_banner_response
  case $warning_banner_response in
    [Yy]|[Yy][Ee][Ss]) warning_banner ;;
    [Nn]|[Nn][Oo]) echo "バナーは変更されませんでした" ;;
    *) echo "不明なコマンドです..." ;;
  esac

  echo -n "SELinux がポート22以外のSSHに干渉する可能性があります。確認しますか？ (y/n) "
  read selinux_check_response
  case $selinux_check_response in
    [Yy]|[Yy][Ee][Ss]) selinux_check ;;
    [Nn]|[Nn][Oo]) echo "SELinux は確認されませんでした。" ;;
    *) echo "不明なコマンドです..." ;;
  esac

  echo -n "FirewallD がSSHをブロックする可能性があります。確認しますか？ (y/n) "
  read firewalld_check_response
  case $firewalld_check_response in
    [Yy]|[Yy][Ee][Ss]) firewalld_check ;;
    [Nn]|[Nn][Oo]) echo "FirewallD は確認されませんでした。" ;;
    *) echo "不明なコマンドです..." ;;
  esac
}

# 上記の関数をクイックに実行する関数
function quick_config() {
  check_root
  sshd_config_check
  backup_sshd_config
  change_protocol
  root_login
  ssh_port
  max_auth
  empty_passwords
  login_gt
  disable_pw
  disable_rhosts
  warning_banner
  selinux_check
  firewalld_check
}

# スクリプトの実行モードを確認し、インタラクティブまたはクイックで処理を進める
if [ "$1" == "i" ]; then
  guided_config
  echo "完了しました！ sshd を再起動してください！"
elif [ "$1" == "q" ]; then
  quick_config
  echo "完了しました！ sshd を再起動してください！"
else
  echo "インタラクティブモード 'i' またはクイックモード 'q' でスクリプトを開始してください。"
fi
