#!/bin/bash

# CRON設定例
# 29,59 * * * * /usr/local/backup.sh >> /var/log/backup_script.log 2>&1

# バックアップ先ディレクトリ
backup_dir="/backup"

# バックアップ対象のディレクトリリスト
# ここに対象ディレクトリを追加してください
backup_targets=(
    "/var/log"
    "/etc"
    # "/home/user/documents"
    # "/var/www/html"
)

# バックアップ先ディレクトリが存在しない場合は作成
mkdir -p "${backup_dir}"

# 現在の日付を取得
current_date=$(date +"%Y%m%d_%H%M")

# 各対象ディレクトリをループ処理
for target in "${backup_targets[@]}"; do
    if [ -d "$target" ]; then
        # ディレクトリ名からスラッシュを除去し、アンダースコアに置換
        dir_name=$(echo "$target" | sed 's/^\///; s/\/$//; s/\//_/g')
        
        # バックアップファイル名を生成
        backup_file="backup_${dir_name}_${current_date}.tar.gz"
        
        # tarコマンドでバックアップを作成
        tar -czvf "${backup_dir}/${backup_file}" -C "$(dirname "$target")" "$(basename "$target")"
        
        echo "バックアップが完了しました: ${backup_dir}/${backup_file}"
    else
        echo "警告: ディレクトリ $target が見つかりません。スキップします。"
    fi
done

echo "全てのバックアップが完了しました。"