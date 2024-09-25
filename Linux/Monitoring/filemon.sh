#!/bin/bash

# 設定ファイルのパス
CONFIG_FILE="./filemon.conf"

# 設定ファイルが存在するか確認
if [ -f "$CONFIG_FILE" ];then
    source "$CONFIG_FILE"
else
    echo "設定ファイルが見つかりません。カレントディレクトリを監視対象に設定します。"
    WATCH_DIRS="./"
    LOG_FILE="./filemon.log"
    PARALLELISM=false
    SLEEP_INTERVAL=60  # デフォルトで60秒の監視間隔
fi

# ディレクトリのリストを配列に変換
WATCH_DIRS=($WATCH_DIRS)

# ハッシュ値を計算する関数
calculate_hash() {
    local file="$1"
    md5sum "$file" | awk '{print $1}'
}

# ファイルの所有者を取得する関数
get_file_owner() {
    local file="$1"
    stat -c '%U' "$file"
}

# ディレクトリ名から適切なファイル名を生成する関数
generate_hash_file_name() {
    local dir="$1"
    local sanitized_dir=$(echo "$dir" | sed 's/[\/\.]/_/g')  # スラッシュやドットをアンダースコアに変換
    echo "./hashes_${sanitized_dir}.txt"
}

# クリーンアップ処理: プロセス終了時に実行される
cleanup() {
    echo "全ての子プロセスを終了します。"

    # 子プロセスを明示的に終了する
    for pid in "${pids[@]}"; do
        kill -TERM "$pid"
        wait "$pid"
    done

    echo "全ての子プロセスが終了しました。プログラムを正常に終了します。"
    exit 0
}

# シグナルをキャッチしてクリーンアップを実行
trap cleanup SIGINT SIGTERM

# ディレクトリの監視を行う関数（並行処理か順次処理かで挙動を変える）
monitor_directory() {
    local dir="$1"
    local hash_file=$(generate_hash_file_name "$dir")
    local loop="$2"  # 並行処理ならtrue, 順次処理ならfalse

    # 初期状態の設定
    if [ ! -f "$hash_file" ];then
        echo "初回実行: ハッシュ値を初期化しています..." | tee -a "$LOG_FILE"
        find "$dir" -type f | while read -r file; do
            hash=$(calculate_hash "$file")
            echo "$file:$hash"
        done > "$hash_file"
    fi

    # 監視ループ（並行処理の場合のみ無限ループ）
    while [ "$loop" = true ] || [ "$loop" = false -a ! -z "$loop" ]; do
        declare -A prev_hashes

        # 前回のハッシュ値をロード
        if [ -f "$hash_file" ];then
            while IFS=":" read -r file hash; do
                prev_hashes["$file"]="$hash"
            done < "$hash_file"
        fi

        # ファイル変更点の検出
        for file in $(find "$dir" -type f); do
            current_hash=$(calculate_hash "$file")
            prev_hash="${prev_hashes[$file]}"

            if [ -z "$prev_hash" ];then
                owner=$(get_file_owner "$file")
                echo "$(date): 新しいファイルが検出されました: $file (所有者: $owner)" | tee -a "$LOG_FILE"
            elif [ "$current_hash" != "$prev_hash" ];then
                owner=$(get_file_owner "$file")
                echo "$(date): ファイルが変更されました: $file (所有者: $owner)" | tee -a "$LOG_FILE"
            fi

            prev_hashes["$file"]="$current_hash"
        done

        # 削除されたファイルの検出
        for file in "${!prev_hashes[@]}"; do
            if [ ! -f "$file" ];then
                echo "$(date): ファイルが削除されました: $file" | tee -a "$LOG_FILE"
                unset prev_hashes["$file"]
            fi
        done

        # ハッシュの更新を保存
        > "$hash_file"
        for file in "${!prev_hashes[@]}"; do
            echo "$file:${prev_hashes[$file]}" >> "$hash_file"
        done

        # 並行処理（無限ループの場合）の場合にスリープ
        if [ "$loop" = true ]; then
            sleep "$SLEEP_INTERVAL"
        else
            break  # 順次処理の場合は1回で終了
        fi
    done
}

# 関数をエクスポートしてサブシェルで使用可能にする
export -f monitor_directory calculate_hash get_file_owner generate_hash_file_name

# 複数のディレクトリを並行して監視するためのプロセスIDリスト
pids=()

# PARALLELISMの値に応じて処理方法を変更
if [ "$PARALLELISM" = true ]; then
    # 並行処理
    for dir in "${WATCH_DIRS[@]}"; do
        monitor_directory "$dir" true &  # 並行処理（バックグラウンドで無限ループ実行）
        pids+=($!)
    done

    # 子プロセスが終了するのを待つ
    wait "${pids[@]}"
else
    # 順次処理: すべてのディレクトリを順番に監視し、最後にスリープ
    while true; do
        for dir in "${WATCH_DIRS[@]}"; do
            monitor_directory "$dir" false  # 1回だけ監視処理を実行
        done
        # すべてのディレクトリを監視した後にスリープ
        sleep "$SLEEP_INTERVAL"
    done
fi
