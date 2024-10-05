#!/bin/bash

# 色の定義
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# エラーメッセージを表示する関数
show_error() {
    echo -e "${RED}エラー: $1${NC}" >&2
}

# 使用法を表示する関数
show_usage() {
    echo "使用法: $0 <ディレクトリ1> <ディレクトリ2>"
}

# 引数の数をチェック
if [ $# -ne 2 ]; then
    show_usage
    exit 1
fi

# 引数で指定されたディレクトリが存在するかチェック
if [ ! -d "$1" ] || [ ! -d "$2" ]; then
    show_error "指定されたディレクトリが存在しません。"
    exit 1
fi

# 絶対パスに変換
dir1=$(realpath "$1")
dir2=$(realpath "$2")

# diffコマンドの存在確認
if ! command -v diff &> /dev/null; then
    show_error "diffコマンドが見つかりません。インストールしてください。"
    exit 1
fi

# ディレクトリの再帰的な比較と出力の整形
diff_output=$(diff -r "$dir1" "$dir2" 2>&1)
diff_exit_code=$?

if [ $diff_exit_code -eq 0 ]; then
    echo "差分はありません。"
elif [ $diff_exit_code -eq 1 ]; then
    added_files=()
    deleted_files=()

    while IFS= read -r line; do
        if [[ $line == Only* ]]; then
            dir=$(echo "$line" | cut -d' ' -f3 | sed 's/:$//')
            file=$(echo "$line" | cut -d' ' -f4)
            if [[ $dir == "$dir1"* ]]; then
                deleted_files+=("$dir/$file")
            else
                added_files+=("$dir/$file")
            fi
        fi
    done <<< "$diff_output"

    {
        for file in "${added_files[@]}"; do
            echo "+ $file"
        done
        for file in "${deleted_files[@]}"; do
            echo "- $file"
        done
    } | sort | while IFS= read -r line; do
        if [[ ${line:0:1} == "+" ]]; then
            echo -e "${GREEN}${line}${NC}"
        else
            echo -e "${RED}${line}${NC}"
        fi
    done
else
    show_error "diff コマンドの実行中にエラーが発生しました。"
    echo "$diff_output" >&2
fi
