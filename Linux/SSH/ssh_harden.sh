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

# OSの種類を判別する関数
function detect_os() {
  if grep -q "Ubuntu" /etc/os-release; then
    OS="Ubuntu"
  elif grep -q "Rocky" /etc/os-release; then
    OS="Rocky"
  elif grep -q "CentOS Linux 7" /etc/os-release; then
    OS="CentOS7"
  else
    echo "サポートされていないOSです。"
    exit 1
  fi
  echo "OS: $OS が検出されました。"
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
    if [[ -f $SSHD_CONF_LOC ]]; then
      echo "指定されたパスに sshd_config が見つかりました。"
      sshd_config_check  # 再度チェックを行う
    else
      echo "指定されたパスに sshd_config が見つかりません。スクリプトを終了します。" 1>&2
      exit 1
    fi
  fi
}


# ファイアウォールの設定を更新する関数 (UFW)
function ufw_update() {
  if [[ "$(ufw status | grep -w active)" ]]; then
    echo "UFW は有効です。ポート番号 $port_number を許可します。"
    ufw allow $port_number/tcp
    ufw reload  # 設定を反映させるためにリロード
    echo "UFW でポート番号 $port_number を許可しました。"
  else
    if [ -z "$1" ]; then
      # インタラクティブモードでは確認を求める
      echo -n "UFW は無効です。UFW を有効にしてポート番号を許可しますか？ (y/n): "
      read ufw_enable_response
      if [[ $ufw_enable_response == "y" || $ufw_enable_response == "Y" ]]; then
        echo "UFW を有効にしてポート番号を許可します。"
        ufw --force enable
        ufw allow $port_number/tcp
        ufw reload
        echo "UFW が有効化され、ポート番号 $port_number を許可しました。"
      else
        echo "UFW は有効化されませんでした。手動で設定してください。"
      fi
    else
      # クイックモードでは有効化されていない場合でもルールを追加し、リロードはしない
      if [[ "$(ufw status | grep -w inactive)" ]]; then
        echo "UFW が無効ですが、ポート番号 $port_number のルールを追加します。"
        ufw allow $port_number/tcp
        echo "UFW が無効化されたままですが、ルールは追加されました。"
      else
        # UFW が有効化されている場合の処理
        echo "UFW は有効です。ポート番号 $port_number を許可します。"
        ufw allow $port_number/tcp
        ufw reload
        echo "UFW でポート番号 $port_number を許可しました。"
      fi
    fi
  fi
}

# ファイアウォールの設定を更新する関数 (firewalld)
function firewalld_update() {
  firewalld_state=$(firewall-cmd --state 2>&1)

  if [[ "$firewalld_state" == "running" ]]; then
    # firewalld が有効化されている場合は通常通り処理を行う
    firewall-cmd --permanent --zone=public --add-port=$port_number/tcp
    if [[ $? -eq 0 ]]; then
      # 追加が成功した場合にのみメッセージを表示
      firewall-cmd --reload
      echo "firewalld でポート番号 $port_number を許可しました。"
    else
      echo "ポートの追加に失敗しました。"
    fi
  else
    # firewalld が無効化されている場合はポート設定をスキップ
    if [ -z "$1" ]; then
      # インタラクティブモードでは確認を求める
      echo -n "firewalld は無効です。firewalld を有効にしてポート番号を許可しますか？ (y/n): "
      read firewalld_enable_response
      if [[ $firewalld_enable_response == "y" || $firewalld_enable_response == "Y" ]]; then
        systemctl start firewalld.service
        firewall-cmd --permanent --zone=public --add-port=$port_number/tcp
        firewall-cmd --reload
        echo "firewalld が有効化され、ポート番号 $port_number を許可しました。"
      else
        echo "firewalld は無効のままです。ポートの設定は行われませんでした。"
      fi
    else
      # クイックモードでは無効化状態でポート設定をスキップし、メッセージを表示
      echo "firewalld が無効のため、ポート番号 $port_number のルールは追加されませんでした。"
    fi
  fi
}



# SELinux と Firewall の確認と設定 (firewalld / UFW)
function firewall_check() {
  if [[ $OS == "Ubuntu" ]]; then
    # Ubuntu用のUFW対応
    echo -n "UFW が SSH ポートをブロックする可能性があります。設定を更新しますか？ (y/n): "
    read ufw_check_response
    case $ufw_check_response in
      [Yy]|[Yy][Ee][Ss]) ufw_update ;;
      [Nn]|[Nn][Oo]) echo "UFW は確認されませんでした。" ;;
      *) echo "不明なコマンドです..." ;;
    esac
  elif [[ $OS == "Rocky" || $OS == "CentOS7" ]]; then
    # Rocky や CentOS 用の firewalld 対応
    echo -n "firewalld が SSH をブロックする可能性があります。設定を更新しますか？ (y/n): "
    read firewalld_check_response
    case $firewalld_check_response in
      [Yy]|[Yy][Ee][Ss]) firewalld_update ;;
      [Nn]|[Nn][Oo]) echo "firewalld は確認されませんでした。" ;;
      *) echo "不明なコマンドです..." ;;
    esac
  fi
}

# sshd_config のバックアップを作成する関数
function backup_sshd_config() {
  cp $SSHD_CONF_LOC . || { echo "バックアップに失敗しました。"; exit 1; }
  echo "sshd_config を $(pwd) にバックアップしました"
}

# SSHプロトコルを変更する関数
function change_protocol() {
  sed -i -e 's/^.*Protocol.*$/Protocol 2/' $SSHD_CONF_LOC
  echo "SSH プロトコルを 2 に変更しました。"
}

# root ログインの許可設定を変更する関数
function root_login() {
  sed -i -e 's/^.*PermitRootLogin.*$/PermitRootLogin no/' $SSHD_CONF_LOC
  echo "root ログインを無効にしました。"
}

# SSHポートを変更する関数（引数付き）
function ssh_port() {
  if [ -z "$1" ]; then
    echo -n "希望するポート番号を入力してください (1-65535): "
    read port_number
  else
    port_number=$1
  fi

  if [ $port_number -gt 0 -a $port_number -lt 65536 ]; then
    sed -i -e "s/^.*Port.*$/Port $port_number/" $SSHD_CONF_LOC
    echo "SSH ポートを $port_number に設定しました。"
  else
    echo "1 から 65535 の間のポート番号を指定してください。"
    if [ -z "$1" ];then ssh_port; fi
  fi
}

# 最大認証試行回数を変更する関数（引数付き）
function max_auth() {
  if [ -z "$1" ]; then
    echo -n "許可する最大認証試行回数を入力してください (1-10): "
    read auth_attempts
  else
    auth_attempts=$1
  fi

  if [ $auth_attempts -gt 0 -a $auth_attempts -lt 11 ]; then
    sed -i -e "s/^.*MaxAuthTries.*$/MaxAuthTries $auth_attempts/" $SSHD_CONF_LOC
    echo "最大認証試行回数を $auth_attempts に設定しました。"
  else
    echo "1 から 10 の間で指定してください。"
    if [ -z "$1" ]; then max_auth; fi
  fi
}

# 空のパスワードを無効化する関数
function empty_passwords() {
  sed -i -e 's/^.*PermitEmptyPasswords.*$/PermitEmptyPasswords no/' $SSHD_CONF_LOC
  echo "空のパスワードを無効にしました。"
}

# ログインの猶予時間を変更する関数（引数付き）
function login_gt() {
  if [ -z "$1" ]; then
    echo -n "希望する猶予時間を秒単位で入力してください (5-120): "
    read grace_time
  else
    grace_time=$1
  fi

  if [ $grace_time -gt 4 -a $grace_time -lt 121 ]; then
    sed -i -e "s/^.*LoginGraceTime.*$/LoginGraceTime $grace_time/" $SSHD_CONF_LOC
    echo "ログイン猶予時間を $grace_time 秒に設定しました。"
  else
    echo "5 から 120 の間の猶予時間を指定してください。"
    if [ -z "$1" ]; then login_gt; fi
  fi
}

# パスワード認証を無効化する関数
function disable_pw() {
  sed -i -e 's/^.*PasswordAuthenticat.*$/PasswordAuthentication no/g' $SSHD_CONF_LOC
  echo "パスワード認証を無効にしました。"
}

# rhosts 認証を無効化する関数
function disable_rhosts() {
  sed -i -e 's/^.*IgnoreRhosts.*$/IgnoreRhosts yes/' $SSHD_CONF_LOC
  echo "rhosts 認証を無効にしました。"
}

# 警告バナーを設定する関数（クイックモードでは自動設定）
function warning_banner() {
  if [ -z "$1" ]; then
    # インタラクティブモードでバナー編集を行う
    touch /etc/ssh/sshd_banner
    cat >/etc/ssh/sshd_banner <<EOF
   WARNING : Unauthorized access to this system is forbidden and will be
   prosecuted by law. By accessing this system, you agree that your actions
   may be monitored if unauthorized usage is suspected.
EOF
    vi /etc/ssh/sshd_banner
  else
    # クイックモードでバナーを自動設定
    cat >/etc/ssh/sshd_banner <<EOF
   WARNING : Unauthorized access to this system is forbidden and will be
   prosecuted by law. By accessing this system, you agree that your actions
   may be monitored if unauthorized usage is suspected.
EOF
  fi
  sed -i -e 's=^.*Banner.*$=Banner /etc/ssh/sshd_banner=' $SSHD_CONF_LOC
  echo "警告バナーを設定しました。"
}

# SELinux の設定を更新する関数
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

# SELinux が Enforcing モードか Permissive モードか確認し、自動化する関数
function selinux_check() {
  if command -v getenforce > /dev/null 2>&1; then
    if [[ "$(getenforce)" == "Enforcing" ]]; then
      if [ -z "$1" ]; then
        # インタラクティブモードでは確認を求める
        echo "SELinux は Enforcing モードで動作しています。"
        echo "ポート番号を変更した場合、SELinux の設定を更新する必要があります。"
        echo -n "SELinux を更新しますか？ (y/n) "
        read selinux_update_response
        case $selinux_update_response in
          [Yy]|[Yy][Ee][Ss]) selinux_update ;;
          [Nn]|[Nn][Oo]) echo "SELinux は変更されません。" ;;
          *) echo "不明なコマンドです..." ;;
        esac 
      else
        # クイックモードでは自動的にSELinuxを更新
        echo "SELinux を自動的に更新しています..."
        selinux_update
      fi
    elif [[ "$(getenforce)" == "Permissive" ]]; then
      if [ -z "$1" ]; then
        # インタラクティブモードで確認
        echo "SELinux は Permissive モードで動作しています。"
        echo "ポート番号を変更した場合、SELinux の設定を更新する必要があります。"
        echo -n "SELinux を更新しますか？ (y/n) "
        read selinux_update_response
        case $selinux_update_response in
          [Yy]|[Yy][Ee][Ss]) selinux_update ;;
          [Nn]|[Nn][Oo]) echo "SELinux は変更されません。" ;;
          *) echo "不明なコマンドです..." ;;
        esac
      else
        # クイックモードでは自動的にSELinuxを更新
        echo "SELinux を自動的に更新しています..."
        selinux_update
      fi
    fi
  else
    echo "SELinux はインストールされていません。"
  fi
}


# sshd を再起動する関数（クイックモードでは自動的に再起動）
function restart_sshd() {
  if [ -z "$1" ]; then
    echo -n "sshd を再起動しますか？ (y/n): "
    read restart_response
    if [[ $restart_response == "y" || $restart_response == "Y" ]]; then
      if systemctl restart sshd 2>/dev/null; then
        echo "sshd を再起動しました。"
      else
        echo "sshd.service が見つかりませんでした。手動で再起動を試みてください。"
      fi
    else
      echo "sshd の再起動をスキップしました。手動で再起動してください。"
    fi
  else
    # クイックモードで自動再起動
    if systemctl restart sshd 2>/dev/null; then
      echo "sshd を再起動しました。"
    else
      echo "sshd.service が見つかりませんでした。手動で再起動を試みてください。"
    fi
  fi
}


# クイックモード用の関数 (自動実行)
function quick_config() {
  check_root
  detect_os
  sshd_config_check
  
  backup_sshd_config
  change_protocol
  root_login
  ssh_port 2222
  max_auth 5
  empty_passwords
  login_gt 30
  # disable_pw  # PW認証は無効化しない
  disable_rhosts
  warning_banner auto
  selinux_check auto
  # クイックモードでは自動でファイアウォール設定を更新、無効化されている場合はスキップ
  if [[ $OS == "Ubuntu" ]]; then
    ufw_update auto
  else
    firewalld_update auto
  fi
  # restart_sshd auto  # クイックモードではsshdを再起動しない
  echo "sshdは手動で再起動してください。"
}

# インタラクティブモードでの実行 (ユーザー確認)
function guided_config() {
  check_root
  detect_os
  sshd_config_check
  
  echo -n "sshd_config をバックアップしますか？ (y/n): "
  read backup_response
  case $backup_response in
    [Yy]|[Yy][Ee][Ss]) backup_sshd_config ;;
    [Nn]|[Nn][Oo]) echo "バックアップは作成されませんでした。" ;;
    *) echo "不明なコマンドです..." ;;
  esac

  echo -n "推奨設定: プロトコル 2 のみに変更しますか？ (y/n): "
  read protocol_response
  case $protocol_response in
    [Yy]|[Yy][Ee][Ss]) change_protocol ;;
    [Nn]|[Nn][Oo]) echo "プロトコルは変更されませんでした。" ;;
    *) echo "不明なコマンドです..." ;;
  esac

  echo -n "推奨設定: root ログインを無効にしますか？ (y/n): "
  read root_login_response
  case $root_login_response in
    [Yy]|[Yy][Ee][Ss]) root_login ;;
    [Nn]|[Nn][Oo]) echo "root ログインは無効化されませんでした。" ;;
    *) echo "不明なコマンドです..." ;;
  esac

  echo -n "SSH ポートを変更しますか？ (y/n): "
  read ssh_port_response
  case $ssh_port_response in
    [Yy]|[Yy][Ee][Ss]) ssh_port ;;
    [Nn]|[Nn][Oo]) echo "ポートは変更されませんでした。" ;;
    *) echo "不明なコマンドです..." ;;
  esac

  echo -n "最大認証試行回数を変更しますか？ (y/n): "
  read authtries_response
  case $authtries_response in
    [Yy]|[Yy][Ee][Ss]) max_auth ;;
    [Nn]|[Nn][Oo]) echo "最大認証試行回数は変更されませんでした。" ;;
    *) echo "不明なコマンドです..." ;;
  esac

  echo -n "空のパスワードを無効化しますか？ (y/n): "
  read empty_pw_response
  case $empty_pw_response in
    [Yy]|[Yy][Ee][Ss]) empty_passwords ;;
    [Nn]|[Nn][Oo]) echo "空のパスワードは無効化されませんでした。" ;;
    *) echo "不明なコマンドです..." ;;
  esac

  echo -n "ログイン猶予時間を変更しますか？ (y/n): "
  read login_gt_response
  case $login_gt_response in
    [Yy]|[Yy][Ee][Ss]) login_gt ;;
    [Nn]|[Nn][Oo]) echo "ログイン猶予時間は変更されませんでした。" ;;
    *) echo "不明なコマンドです..." ;;
  esac

  echo -n "パスワード認証を無効化しますか？ (y/n): "
  read disable_pw_response
  case $disable_pw_response in
    [Yy]|[Yy][Ee][Ss]) disable_pw ;;
    [Nn]|[Nn][Oo]) echo "パスワード認証は無効化されませんでした。" ;;
    *) echo "不明なコマンドです..." ;;
  esac

  echo -n "rhosts 認証を無効化しますか？ (y/n): "
  read disable_rhosts_response
  case $disable_rhosts_response in
    [Yy]|[Yy][Ee][Ss]) disable_rhosts ;;
    [Nn]|[Nn][Oo]) echo "rhosts 認証は無効化されませんでした。" ;;
    *) echo "不明なコマンドです..." ;;
  esac

  echo -n "警告バナーを設定しますか？ (y/n): "
  read warning_banner_response
  case $warning_banner_response in
    [Yy]|[Yy][Ee][Ss]) warning_banner ;;
    [Nn]|[Nn][Oo]) echo "バナーは設定されませんでした。" ;;
    *) echo "不明なコマンドです..." ;;
  esac

  # SELinuxとファイアウォールの確認と設定
  selinux_check
  firewall_check

  # SSHD 再起動
  restart_sshd
}

# スクリプトの実行モードを確認し、インタラクティブまたはクイックで処理を進める
if [ "$1" == "i" ]; then
  guided_config
  echo "== Done ==="
elif [ "$1" == "q" ];then
  quick_config
  echo "== Done ==="
else
  echo "インタラクティブモード 'i' またはクイックモード 'q' でスクリプトを開始してください。"
fi
