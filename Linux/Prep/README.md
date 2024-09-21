# 初期フェーズ作業リスト

### **Step 1: 踏み台サーバのへのアクセス**

---

踏み台サーバにSSHで接続する際、以下のコマンドを使用します。

```bash
# user01, 10.x.x.xは適宜置き換えてください。
ssh -MS /tmp/sock1 -p 22 user01@10.x.x.x
```

### Step 2: 初期タスク用スクリプトの実行

---

[このスクリプト](./init_task.sh)の内容を`init_task.sh`としてファイルにコピペして保存します。

```bash
vim init_task.sh
sudo chmod +x init_task.sh
sudo bash init_task.sh
```

<aside>
💡

`init_task.sh`では、以下の作業を行います。

スクリプトが実行できている場合は[Step 3](#step-3-出力されたファイルを踏み台サーバにコピーする)へ進んでください。

</aside>

**＜手動で実行する場合＞**

1. バックアップ管理者アカウントの作成
    
    ```bash
    # アカウントを作成
    adduser --disabled-password --gecos "" bkadmin
    
    # 管理者グループに追加
    usermod -aG sudo bkadmin
    
    # 2番目のアカウントを作成
    adduser --disabled-password --gecos "" bkadmin2
    
    # 2番目のアカウントも管理者グループに追加
    usermod -aG sudo bkadmin2
    ```
    
2. 通常ユーザのリストを取得
    
    ```bash
    # user_list.txt からは、変更対象から外したいユーザを削除しておくこと。
    awk -F: '($3 >= 1000) && ($3 != 65534)' /etc/passwd | cut -d: -f1 > user_list.txt
    ```
    
3. 通常ユーザのパスワードを変更
    
    ```bash
    
    # new_passwordを任意の文字列に置き換えて実行すること。
    while IFS= read -r user; do echo "$user:new_password" | sudo chpasswd; done < user_list.txt
    ```
    

### Step 3: 出力**されたファイルを踏み台サーバにコピーする**

---

```bash
# 対象サーバ側から実行する場合：
# localuser, 192.168.x.x, /home/localuserは適宜置き換えてください。
# ※踏み台サーバでSSH接続を受け付けていること
scp /path/to/sysinfo.txt localuser@192.168.x.x:/home/localuser
scp /path/to/userlist.txt localuser@192.168.x.x:/home/localuser
scp /path/to/user_list.txt localuser@192.168.x.x:/home/localuser
scp /path/to/script.log localuser@192.168.x.x:/home/localuser

# 踏み台サーバ側から実行する場合：
# user01, remoteip, /path/to/~は適宜置き換えてください。
# ※パーミッションに注意！（対象サーバ側で権限の設定が必要：644）
scp -o controlpath=/tmp/sock1 user01@remoteip:/path/to/sysinfo.txt .
scp -o controlpath=/tmp/sock1 user01@remoteip:/path/to/userlist.txt .
scp -o controlpath=/tmp/sock1 user01@remoteip:/path/to/user_list.txt .
scp -o controlpath=/tmp/sock1 user01@remoteip:/path/to/script.log .
```

### Step 4: 出力されたファイルを完全に削除する（rmでは消さないで！）

---

```bash
# 対象サーバ側で実行
sudo shred -uz sysinfo.txt
sudo shred -uz userlist.txt
sudo shred -uz user_list.txt
sudo shred -uz script.log

# 1行で。
sudo shred -uz sysinfo.txt userlist.txt user_list.txt script.log
```

### Step 5: 

---